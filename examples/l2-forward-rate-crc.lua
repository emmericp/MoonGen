--- Forward packets between two ports
-- local lm     = require "libmoon"
local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local ts     = require "timestamping"
local histogram = require "histogram"
local stats  = require "stats"
local log    = require "log"
local timer		= require "timer"

-- local limiter = require "software-ratecontrol"

function configure(parser)
	parser:description("Forward traffic between interfaces with moongen rate control")
	parser:argument("dev", "Devices to use, specify the same device twice to echo packets."):args(2):convert(tonumber)
	--parser:option("-r --rate", "Transmit rate in Mpps."):args(1):default(2):convert(tonumber)
	parser:argument("rate", "Forwarding rates in Mbps (two values for two links)"):args(2):convert(tonumber)
	parser:option("-t --threads", "Number of threads per forwarding direction using RSS."):args(1):convert(tonumber):default(1)
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
			rxDescs = 4096,
			dropEnable = true,
			disableOffloads = true
		}
	end
	device.waitForLinks()

	-- print stats
	stats.startStatsTask{devices = args.dev}

	-- start forwarding tasks
	for i = 1, args.threads do
		print("dev is ",tonumber(args.dev[1]["id"]))
		--rateLimiter1 = limiter:new(args.dev[2]:getTxQueue(i - 1), "cbr", 1 / args.rate[1] * 1000)
		mg.startTask("forward", args.dev[1]:getRxQueue(i - 1), args.dev[2]:getTxQueue(i - 1), args.dev[2], args.rate[1])
		-- bidirectional fowarding only if two different devices where passed
		if args.dev[1] ~= args.dev[2] then
			mg.startTask("forward", args.dev[2]:getRxQueue(i - 1), args.dev[1]:getTxQueue(i - 1), args.dev[1], args.rate[2])
		end
	end
	mg.waitForTasks()
end

function forward(rxQueue, txQueue, txDev, rate)
	print("forward with rate "..rate)
	local ETH_DST	= "11:12:13:14:15:16"
	local pattern = "cbr"
	local numThreads = 1

	local count_hist = histogram:new()
	local size_hist = histogram:new()
	
	local linkspeed = txDev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)

	-- larger batch size is useful when sending it through a rate limiter
	local bufs = memory.createBufArray()  --memory:bufArray()  --(128)
	local dist = pattern == "poisson" and poissonDelay or function(x) return x end
	while mg.running() do
		-- receive one or more packets from the queue
		local count = rxQueue:recv(bufs)

		count_hist:update(count)

		-- send out all received bufs on the other queue
		-- the bufs are free'd implicitly by this function
		-- txQueue:sendN(bufs, count)

		-- There is a problem here when we are just forwarding packets
		-- if the link is idle, when the packet arrives, there should be no delay
		-- we need to keep track of the size and tx time of the last pkt sent, and then
		-- look up the current time in order to compute the remaining delay to add to the current packet
		-- the approach here only applies when we have an unlimited stream of packets
		-- should all that be implemented here, or in sendWithDelay?
		--
		-- The answer is to change the way CRC rate control works
		-- When a packet is to be sent, it should be sent immediately, but followed up with
		-- a series of bad packets that take up the extra time the packet /should/ have taken
		-- at the desired emulated rate.
		-- This approach will cause some issues when the desired speed is between 500-1000,
		-- and the good packets are small.  In that case the size of the bad packet we need may
		-- often be less than the min frame size.  As long as the rate is less than 1/2 line
		-- speed, this should never be a problem, though.
		--
		-- Coming back to this later, and I disagree with what I wrote before.  The dummy
		-- packets shouldbe sent out before the actual packet.  Otherwise the good packet
		-- could be complete received before it would have even completed sending at the
		-- reduced rate.
		for _, buf in ipairs(bufs) do
			if (buf ~= nil) then
				local pktSize = buf.pkt_len + 24
				--print("forwarding packet of size ",pktSize)
				--buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - pktSize - 24))
				--buf:setDelay((pktSize+24) * (linkspeed/rate - 1) )
				size_hist:update(buf.pkt_len)
				buf:setDelay((pktSize) * (linkspeed/rate - 1) )
			end
		end

		-- the rate here doesn't affect the result afaict.  It's just to help decide the size of the bad pkts
		txQueue:sendWithDelay(bufs, rate * numThreads, count)
		--txQueue:sendWithDelay(bufs)
	end
	
	count_hist:print()
	count_hist:save("pkt-count-distribution-histogram-"..tonumber(txDev["id"])..".csv")
	size_hist:print()
	size_hist:save("pkt-size-distribution-histogram-"..tonumber(txDev["id"])..".csv")
end


function forward2(rxQueue, txQueue, rateLimiter)
	-- a bufArray is just a list of buffers that we will use for batched forwarding
	local bufs = memory.bufArray()
	while mg.running() do -- check if Ctrl+c was pressed
		-- receive one or more packets from the queue
		local count = rxQueue:recv(bufs)
		-- send out all received bufs on the other queue
		-- the bufs are free'd implicitly by this function
		-- txQueue:sendN(bufs, count)
		rateLimiter:send(bufs)
	end
end

