local mg      = require "moongen"
local memory  = require "memory"
local device  = require "device"
local ts      = require "timestamping"
local stats   = require "stats"
local log     = require "log"
local limiter = require "software-ratecontrol"
local pipe    = require "pipe"
local ffi     = require "ffi"
local libmoon = require "libmoon"
local histogram = require "histogram"

local PKT_SIZE	= 60

function configure(parser)
	parser:description("Forward traffic between interfaces with moongen rate control")
	parser:option("-d --dev", "Devices to use, specify the same device twice to echo packets."):args(2):convert(tonumber)
	--parser:option("-r --rate", "Transmit rate in Mpps."):args(1):default(2):convert(tonumber)
	parser:option("-r --rate", "Forwarding rates in Mbps (two values for two links)"):args(2):convert(tonumber)
	parser:option("-t --threads", "Number of threads per forwarding direction using RSS."):args(1):convert(tonumber):default(1)
	parser:option("-l --latency", "Fixed emulated latency (in ms) on the link."):args(2):convert(tonumber):default({0,0})
	parser:option("-x --xlatency", "Extra exponentially distributed latency, in addition to the fixed latency (in ms)."):args(2):convert(tonumber):default({0,0})
	parser:option("-q --queuedepth", "Maximum number of bytes to hold in the delay line"):args(2):convert(tonumber):default({0,0})
	parser:option("-o --loss", "Rate of packet drops"):args(2):convert(tonumber):default({0,0})
	parser:option("-c --concealedloss", "Rate of concealed packet drops"):args(2):convert(tonumber):default({0,0})
	parser:option("-u --catchuprate", "After a concealed loss, this rate will apply to the backed-up frames."):args(2):convert(tonumber):default({0,0})
	return parser:parse()
end


function master(args)
	-- configure devices
	for i, dev in ipairs(args.dev) do
		print(i,dev)
		args.dev[i] = device.config{
			port = dev,
			txQueues = args.threads,
			rxQueues = args.threads,
			rssQueues = 0,
			rssFunctions = {},
			rxDescs = 4096,
			dropEnable = true,
			disableOffloads = true
		}
		print(args.dev[i]["id"])
	end
	device.waitForLinks()

	-- print stats
	stats.startStatsTask{devices = args.dev}
	
	-- create the ring buffers
	-- should set the size here, based on the line speed and latency, and maybe desired queue depth
	local qdepth1 = args.queuedepth[1]
	if qdepth1 < 1 then
		qdepth1 = math.floor((args.latency[1] * args.rate[1] * 1000)/8)
	end
	local qdepth2 = args.queuedepth[2]
	if qdepth2 < 1 then
		qdepth2 = math.floor((args.latency[2] * args.rate[2] * 1000)/8)
	end
	local ring1 = pipe:newBytesizedtxRing(qdepth1, -1, args.dev[1]["id"])
	local ring2 = pipe:newBytesizedtxRing(qdepth2, -1, args.dev[2]["id"])

	-- start the forwarding tasks
	for i = 1, args.threads do
		mg.startTask("forward", ring1, args.dev[1]:getTxQueue(i - 1), args.dev[1], args.rate[1], args.latency[1], args.xlatency[1], args.loss[1], args.concealedloss[1], args.catchuprate[1])
		if args.dev[1] ~= args.dev[2] then
			mg.startTask("forward", ring2, args.dev[2]:getTxQueue(i - 1), args.dev[2], args.rate[2], args.latency[2], args.xlatency[2], args.loss[2], args.concealedloss[2], args.catchuprate[2])
		end
	end

	-- start the receiving/latency tasks
	for i = 1, args.threads do
		mg.startTask("receive", ring1, args.dev[2]:getRxQueue(i - 1), args.dev[2])
		if args.dev[1] ~= args.dev[2] then
			mg.startTask("receive", ring2, args.dev[1]:getRxQueue(i - 1), args.dev[1])
		end
	end

	mg.waitForTasks()
end


function receive(ring, rxQueue, rxDev)
	local bufs = memory.createBufArray()
	local count = 0
	local count_hist = histogram:new()
	local ringsize_hist = histogram:new()
	local ringbytes_hist = histogram:new()
	local ts = 0
	while mg.running() do
		count = rxQueue:recv(bufs)
		--count_hist:update(count)
		for iix=1,count do
			local buf = bufs[iix]
			--if buf:hasTimestamp() then
			--	ts = buf:getTimestamp()
			--end
			ts = limiter:get_tsc_cycles()
			buf.udata64 = ts
		end
		if count > 0 then
			local num_added = pipe:sendToBytesizedtxRing(ring.ring, bufs, count)
			if (num_added < count) then
				--print("failed to add packets to bstxring "..num_added.."  "..count)
			end
			--ringsize_hist:update(pipe:countBytesizedRing(ring.ring))
			--ringbytes_hist:update(pipe:bytesusedBytesizedRing(ring.ring))
			--print("ring count/usage: ",pipe:countBytesizedRing(ring.ring),pipe:bytesusedBytesizedRing(ring.ring),count)
		end
	end
	count_hist:print()
	count_hist:save("rxq-pkt-count-distribution-histogram-"..rxDev["id"]..".csv")
	ringsize_hist:print()
	ringsize_hist:save("rxq-ringsize-distribution-histogram-"..rxDev["id"]..".csv")
	ringbytes_hist:print()
	ringbytes_hist:save("rxq-ringbytes-distribution-histogram-"..rxDev["id"]..".csv")
end


function forward(ring, txQueue, txDev, rate, latency, xlatency, lossrate, clossrate, catchuprate)
	print("forward with rate "..rate.." and latency "..latency.." and loss rate "..lossrate.." and clossrate "..clossrate.." and catchuprate "..catchuprate)
	local numThreads = 1
	
	local count_hist = histogram:new()
	local size_hist = histogram:new()

	local linkspeed = txDev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)

	local tsc_hz = libmoon:getCyclesFrequency()
	local tsc_hz_ms = tsc_hz / 1000
	local tsc_hz_us = tsc_hz / 1000000
	print("tsc_hz = "..tsc_hz)

	-- larger batch size is useful when sending it through a rate limiter
	local bufs = memory.createBufArray()  --memory:bufArray()  --(128)
	local count = 0

	-- when there is a concealed loss, the backed-up packets can
	-- catch-up at line rate
	local catchup_mode = false
	
	while mg.running() do
		-- receive one or more packets from the queue
		count = pipe:recvFromBytesizedtxRing(ring.ring, bufs, 1)
		--count_hist:update(count)

		for iix=1,count do
			local buf = bufs[iix]

			-- get the buf's arrival timestamp and compare to current time
			local arrival_timestamp = buf.udata64

			-- emulate extra exponential random delay
			local extraDelay = 0.0
			if (xlatency > 0) then
				extraDelay = -math.log(math.random())*xlatency
			end

			-- emulate concealed losses
			local closses = 0
			while (math.random() < clossrate) do
				closses = closses + 1
				if (catchuprate > 0) then
					catchup_mode = true
					--print "entering catchup mode!"
				end
			end
			local send_time = arrival_timestamp + (((closses+1)*latency + extraDelay) * tsc_hz_ms)

			local cur_time = limiter:get_tsc_cycles()
			-- spin/wait until it is time to send this frame
			-- this assumes frame order is preserved
				
			while cur_time < send_time do
				catchup_mode = false
				if not mg.running() then
					return
				end
				cur_time = limiter:get_tsc_cycles()
			end
					
			local pktSize = buf.pkt_len + 24
			--size_hist:update(buf.pkt_len)
			if (catchup_mode) then
				--print "operating in catchup mode!"
				--print("catchup setting delay to "..((pktSize) * (linkspeed/rate - 1)).." on buf ",buf)
				buf:setDelay((pktSize) * (linkspeed/catchuprate - 1))
			else
				buf:setDelay((pktSize) * (linkspeed/rate - 1))
			end

			--if count > 0 then
			if count > 0 then
				-- the rate here doesn't affect the result afaict.  It's just to help decide the size of the bad pkts
				txQueue:sendWithDelayLoss(bufs, rate * numThreads, lossrate, count)
			end
		end   -- if count > 0 then
	end   -- while mg.running() do
	count_hist:print()
	count_hist:save("pkt-count-distribution-histogram-"..tonumber(txDev["id"])..".csv")
	size_hist:print()
	size_hist:save("pkt-size-distribution-histogram-"..tonumber(txDev["id"])..".csv")
end








