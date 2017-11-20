local mg      = require "moongen"
local memory  = require "memory"
local device  = require "device"
local ts      = require "timestamping"
local stats   = require "stats"
local hist    = require "histogram"
local log     = require "log"
local limiter = require "software-ratecontrol"

local PKT_SIZE	= 60
local ETH_DST	= "11:12:13:14:15:16"

function master(txPort, rate, rc, pattern, threads)
	if not txPort or not rate or not rc then
		return print("usage: txPort rate|us hw|sw|moongen cbr|poisson|custom [threads]")
	end
	rate = rate or 2
	threads = threads or 1
	pattern = pattern or "cbr"
	if pattern == "cbr" and threads ~= 1 then
		return log:error("cbr only supports one thread")
	end
	local txDev = device.config{port = txPort, txQueues = threads, disableOffloads = rc ~= "moongen"}
	device.waitForLinks()
	stats.startStatsTask{txDevices = {txDev}}
	for i = 1, threads do
		local rateLimiter
		if rc == "sw" then
			rateLimiter = limiter:new(txDev:getTxQueue(i - 1), pattern, 1 / rate * 1000)
		end
		mg.startTask("loadSlave", txDev:getTxQueue(i - 1), txDev, rate, rc, pattern, rateLimiter, i, threads)
	end
	mg.waitForTasks()
end

function loadSlave(queue, txDev, rate, rc, pattern, rateLimiter, threadId, numThreads)
	local mem = memory.createMemPool(4096, function(buf)
		buf:getUdpPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			pktLength = PKT_SIZE
		}
	end)
	if rc == "hw" then
		local bufs = mem:bufArray()
		if pattern ~= "cbr" then
			return log:error("HW only supports CBR")
		end
		queue:setRate(rate * (PKT_SIZE + 4) * 8)
		mg.sleepMillis(100) -- for good meaasure
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
		end
	elseif rc == "sw" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		local linkSpeed = txDev:getLinkStatus().speed
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			if pattern == "custom" then
				for _, buf in ipairs(bufs) do
					buf:setDelay(rate * linkSpeed / 8)
				end
			end
			rateLimiter:send(bufs)
		end
	elseif rc == "moongen" then
		-- larger batch size is useful when sending it through a rate limiter
		local bufs = mem:bufArray(128)
		local dist = pattern == "poisson" and poissonDelay or function(x) return x end
		while mg.running() do
			bufs:alloc(PKT_SIZE)
			for _, buf in ipairs(bufs) do
				buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - PKT_SIZE - 24))
			end
			queue:sendWithDelay(bufs, rate * numThreads)
		end
	else
		log:error("Unknown rate control method")
	end
end

