local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"
local log		= require "log"
local limiter	= require "ratelimiter"

local PKT_SIZE	= 60
local ETH_DST	= "11:12:13:14:15:16"

function master(txPort, rate, rc, pattern, threads)
	if not txPort or not rate or not rc or (pattern ~= "cbr" and pattern ~= "poisson") then
		return print("usage: txPort rate hw|sw|moongen cbr|poisson [threads]")
	end
	rate = rate or 2
	threads = threads or 1
	if pattern == "cbr" and threads ~= 1 then
		return log:error("cbr only supports one thread")
	end
	local txDev = device.config{ port = txPort, txQueues = threads, disableOffloads = rc ~= "moongen" }
	device.waitForLinks()
	for i = 1, threads do
		local rateLimiter
		if rc == "sw" then
			rateLimiter = limiter:new(txDev:getTxQueue(i - 1), pattern, 1 / rate * 1000)
		end
		dpdk.launchLua("loadSlave", txDev:getTxQueue(i - 1), txDev, rate, rc, pattern, rateLimiter, i, threads)
	end
	dpdk.waitForSlaves()
end

function loadSlave(queue, txDev, rate, rc, pattern, rateLimiter, threadId, numThreads)
	local mem = memory.createMemPool(4096, function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)
	local txCtr
	if rc == "hw" then
		local bufs = mem:bufArray()
		if pattern ~= "cbr" then
			return log:error("HW only supports CBR")
		end
		txCtr = stats:newDevTxCounter(txDev, "plain")
		queue:setRate(rate * (PKT_SIZE + 4) * 8)
		dpdk.sleepMillis(100) -- for good meaasure
		while dpdk.running() do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
			if threadId == 1 then txCtr:update() end
		end
	elseif rc == "sw" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		txCtr = stats:newDevTxCounter(txDev, "plain")
		while dpdk.running() do
			bufs:alloc(PKT_SIZE)
			rateLimiter:send(bufs)
			if threadId == 1 then txCtr:update() end
		end
	elseif rc == "moongen" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		txCtr = stats:newManualTxCounter(txDev, "plain")
		local dist = pattern == "poisson" and poissonDelay or function(x) return x end
		while dpdk.running() do
			bufs:alloc(PKT_SIZE)
			for _, buf in ipairs(bufs) do
				buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - PKT_SIZE - 24))
			end
			--txCtr:updateWithSize(queue:sendWithDelay(bufs), PKT_SIZE)
			txCtr:updateWithSize(queue:sendWithDelay(bufs, rate * numThreads), PKT_SIZE)
		end
	else
		log:error("Unknown rate control method")
	end
	txCtr:finalize()
end

