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
	parser:option("-l --latency", "Fixed emulated latency (in ms) on the link."):args(2):convert(tonumber):default(0)
	parser:option("-x --xlatency", "Extra exponentially distributed latency, in addition to the fixed latency (in ms)."):args(2):convert(tonumber):default(0)
	parser:option("-q --queuedepth", "Maximum number of bytes to hold in the delay line"):args(2):convert(tonumber):default({0,0})
	parser:option("-o --loss", "Rate of packet drops"):args(2):convert(tonumber):default(0)
	parser:option("-c --concealedloss", "Rate of concealed packet drops"):args(2):convert(tonumber):default(0)
	parser:option("-u --catchuprate", "After a concealed loss, this rate will apply to the backed-up frames."):args(2):convert(tonumber):default(0)
	return parser:parse()
end


function master(args)
	-- configure devices
	for i, dev in ipairs(args.dev) do
		args.dev[i] = device.config{
			port = dev,
			txQueues = args.threads,
			rxQueues = args.threads,
			rssQueues = 0,
			rssFunctions = {},
			--rxDescs = 4096,
			--rxDescs = 128,
			--txDescs = 128,
			dropEnable = true,
			disableOffloads = true
		}
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
	local ring1 = pipe:newBytesizedRing(qdepth1)
	local ring2 = pipe:newBytesizedRing(qdepth2)

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
	--print("receive thread...")

	local bufs = memory.createBufArray()
	local count = 0
	local count_hist = histogram:new()
	local histfile = "rxq-pkt-count-distribution-histogram-"..tonumber(rxDev["id"])..".csv"
	print("will save hist to: "..histfile)
	--local last_ts = 0
	--local last_hwts = 0
	while mg.running() do
		count = rxQueue:recv(bufs)
		count_hist:update(count)
		--print("receive thread count="..count)
		--for iix, buf in ipairs(bufs) do
		for iix=1,count do
			local buf = bufs[iix]
			if (buf ~= nil) then
				if (iix > count) then
					print("WARNING receive: iix > count",iix,count)
				end
				--if buf:hasTimestamp() then
				--	local ts = buf:getTimestamp()
				--	buf.udata64 = ts
				--	print("set timestamp to getTimestamp=", ts)
				--else
					local ts = limiter:get_tsc_cycles()
					buf.udata64 = ts
					print("RXRXRX ",buf,ts,buf.udata64)
					--if buf:hasTimestamp() then
					--	local hwts = buf:getTimestamp()
					--	print("arrival timestamps: ",ts, (ts-last_ts), hwts, last_hwts, (hwts-last_hwts))
					--	last_ts = ts
					--	last_hwts = hwts
					--else
					--	print("no hw timestamp!!!")
					--end
					--print("set timestamp to get_tsc_cycles=", ts, count)
				--end
			end
		end
		if count > 0 then
			pipe:sendToBytesizedRing(ring.ring, bufs, count)
			--print("ring count/usage: ",pipe:countBytesizedRing(ring.ring),pipe:bytesusedBytesizedRing(ring.ring),count)
		end
	end
	count_hist:print()
	count_hist:save(histfile)
end


function forward(ring, txQueue, txDev, rate, latency, xlatency, lossrate, clossrate, catchuprate)
	print("forward with rate "..rate.." and latency "..latency.." and loss rate "..lossrate.." and clossrate "..clossrate.." and catchuprate "..catchuprate)
	local numThreads = 1
	
	local count_hist = histogram:new()
	--local size_hist = histogram:new()
	local counthistfile = "pkt-count-distribution-histogram-"..tonumber(txDev["id"])..".csv"
	print("will save hist to: "..counthistfile)

	local linkspeed = txDev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)

	local tsc_hz = libmoon:getCyclesFrequency()
	local tsc_hz_ms = tsc_hz / 1000
	local tsc_hz_us = tsc_hz / 1000000
	print("tsc_hz = "..tsc_hz)

	-- larger batch size is useful when sending it through a rate limiter
	local bufs = memory.createBufArray()  --memory:bufArray()  --(128)
	local count = 0
	print("bufs = ", bufs, bufs.size)
	for iix=1,bufs.size do
		print("\t",iix,bufs[iix])
	end


	-- when there is a concealed loss, the backed-up packets can
	-- catch-up at line rate
	local catchup_mode = false
	
	local cur_time = limiter:get_tsc_cycles()
	print("timing test: ",cur_time)
	local last_time = cur_time
	cur_time = limiter:get_tsc_cycles()
	print("timing test: ",cur_time, last_time, (cur_time-last_time), (cur_time-last_time)/tsc_hz_us)
	last_time = cur_time
	cur_time = limiter:get_tsc_cycles()
	print("timing test: ",cur_time, last_time, (cur_time-last_time), (cur_time-last_time)/tsc_hz_us)
	last_time = cur_time
	cur_time = limiter:get_tsc_cycles()
	print("timing test: ",cur_time, last_time, (cur_time-last_time), (cur_time-last_time)/tsc_hz_us)
	

	while mg.running() do
		-- receive one or more packets from the queue
		--local count = rxQueue:recv(bufs)
		prerecv_time = limiter:get_tsc_cycles()
		--count = pipe:recvFromBytesizedRing(ring.ring, bufs)
		count = pipe:recvFromBytesizedRing(ring.ring, bufs, 1)
		postrecv_time = limiter:get_tsc_cycles()
		if (prerecv_time - prerecv_time) > tsc_hz_us then
			print("time of recvFromBytesizedRing: ",prerecv_time, prerecv_time, (prerecv_time-prerecv_time), (prerecv_time-prerecv_time)/tsc_hz_us)
		end
		count_hist:update(count)

		if count > 0 then
			--print("count=", count)

			local itercount = 0
			--for iix, buf in ipairs(bufs) do
			for iix=1,count do
				local buf = bufs[iix]
				print("iteration "..iix,bufs[iix])				

				itercount = itercount + 1
				if ((iix <= count) and (buf ~= nil)) then
					--print("buf ~= nil")
					-- get the buf's arrival timestamp and compare to current time
					--local arrival_timestamp = buf:getTimestamp()
					local arrival_timestamp = buf.udata64
					--------------------print("arrival timestamp ",arrival_timestamp,ii,buf)
					--local hwtimestamp = buf:getTimestamp()

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
					--print("timestamps", arrival_timestamp, send_time, cur_time)
					-- spin/wait until it is time to send this frame
					-- this assumes frame order is preserved
				
					--if (cur_time > send_time) then
					--	print("latency exceeded before loop: ",cur_time, send_time, (cur_time-send_time), (cur_time-send_time)/tsc_hz_us)
					--end

					--local last_loop_time = limiter:get_tsc_cycles()
					local spinwaited = false
					while cur_time < send_time do
						spinwaited = true
						catchup_mode = false
						if not mg.running() then
							return
						end
						cur_time = limiter:get_tsc_cycles()
						--if ((cur_time-last_loop_time) > 3000000) then
						--	print("inter-loop time: ",cur_time, last_loop_time, (cur_time-last_loop_time), (cur_time-last_loop_time)/tsc_hz_us)
						--end
						--if (cur_time > send_time) then
						--	if ((cur_time - send_time) > 5000) then
						--		print("target latecy will be exceeded by: ",cur_time, send_time, (cur_time-send_time), (cur_time-send_time)/tsc_hz_us)
						--	end
						--end
						--last_loop_time = cur_time
					end
				
					--if (cur_time - send_time) > tsc_hz_ms then
					--	print("target latecy exceeded by: ",cur_time, send_time, (cur_time-send_time), (cur_time-send_time)/tsc_hz_us)
					--end
					--hist:update(tonumber(cur_time - send_time))
	
					local pktSize = buf.pkt_len + 24
					--size_hist:update(buf.pkt_len)
					if (catchup_mode) then
						--print "operating in catchup mode!"
						print("catchup setting delay to "..((pktSize) * (linkspeed/rate - 1)).." on buf ",buf,spinwaited)
						buf:setDelay((pktSize) * (linkspeed/catchuprate - 1))
					else
						print("setting delay to "..((pktSize) * (linkspeed/rate - 1)).." on buf ",buf,spinwaited)
						buf:setDelay((pktSize) * (linkspeed/rate - 1))
					end
					print("delay is now ", buf.udata64, buf, buf.pkt_len)
				end
			end
			print("did so many iterations "..itercount)
			--print("count="..tostring(count))

			--if count > 0 then
			if count > 0 then
				-- the rate here doesn't affect the result afaict.  It's just to help decide the size of the bad pkts
				--local presend_time = limiter:get_tsc_cycles()
				------------------print("calling sendWithDelayLoss ",bufs[0],bufs[0].udata64)
				txQueue:sendWithDelayLoss(bufs, rate * numThreads, lossrate, count)
				--txQueue:sendWithDelay(bufs, rate * numThreads, count)
				--local postsend_time = limiter:get_tsc_cycles()
				--if (postsend_time - presend_time) > 10000000ULL then
				--if (postsend_time - presend_time) > 100*tsc_hz_us then
				--if (postsend_time - presend_time) > 100*tsc_hz_us then
				--	print("abnormal time spent sending: ",postsend_time, presend_time, (postsend_time-presend_time), (postsend_time-presend_time)/tsc_hz_us)
				--end
				--txQueue:sendWithDelay(bufs, rate * numThreads, count)
				--print("sendWithDelay() returned")
			end
		end   -- if count > 0 then
	end   -- while mg.running() do
	count_hist:print()
	count_hist:save("pkt-count-distribution-histogram-"..tonumber(txDev["id"])..".csv")
	--size_hist:print()
	--size_hist:save("pkt-size-distribution-histogram-"..tonumber(txDev["id"])..".csv")
end








