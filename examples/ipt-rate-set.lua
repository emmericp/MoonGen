local mg		= require "moongen"
local memory		= require "memory"
local device		= require "device"
local ts		= require "timestamping"
local hist		= require "histogram"
local log		= require "log"
local timer		= require "timer"
local limiter		= require "software-ratecontrol"

local ETH_DST	= "11:12:13:14:15:16"


function master(txPort, rxPort, pattern, threads, pktSize, ipt, waitTime)
	if not rxPort or not txPort or not threads or not pktSize or not ipt then
		errorf("usage: txPort rxPort threads pktSize interpacket_time(us) [waitTime]")
	end

	if (((pktSize+26)*8) > (1000*ipt)) then
		errorf("requested packet size and inter-packet time is infeasible")
	end

	local rxDev = device.config{ port = rxPort, rxDescs = 4096, dropEnable = true }
	local txDev = device.config{port = txPort, txQueues = threads, disableOffloads = true}
	-- rxDev:wait()
	-- txDev:wait()
	device.waitForLinks()

	local queue = rxDev:getRxQueue(0)
	queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray()
	local times = {}
	local timer = timer:new(waitTime)

	for i = 1, threads do
		-- local pktRate = (1000.0 * rate) / pktSize
		local rateLimiter = limiter:new(txDev:getTxQueue(i - 1), pattern, 1000*ipt)
		mg.startTask("loadSlave", txDev:getTxQueue(i - 1), txDev, rateLimiter, i, threads, pktSize)
	end

	while mg.running() do
		local n = queue:recv(bufs)
		for i = 1, n do
			if timer:expired() then
				local ts = bufs[i]:getTimestamp()
				times[#times + 1] = ts
			end
		end
		total = total + n
		bufs:free(n)
	end

	mg.waitForTasks()

	local pkts = rxDev:getRxStats(port)
	local h = hist:create()
	local last
	for i, v in ipairs(times) do
		if last then
			local diff = v - last
			h:update(diff)
		end
		last = v
	end
	h:print()
	h:save("histogram.csv")
	log[(pkts - total > 0 and "warn" or "info")](log, "Lost packets: " .. pkts - total
		.. " (this can happen if the NIC still receives data after this script stops the receive loop)")
end



function loadSlave(queue, txDev, rateLimiter, threadId, numThreads, pktSize)
	local mem = memory.createMemPool(4096, function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)

	-- larger batch size is useful when sending it through a rate limiter
	local bufs = mem:bufArray(128)
	while mg.running() do
		bufs:alloc(pktSize)
		rateLimiter:send(bufs)
	end
end




