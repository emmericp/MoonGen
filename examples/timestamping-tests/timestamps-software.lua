--- Software timestamping precision test.
local mg		= require "dpdk"
local ts		= require "timestamping"
local device	= require "device"
local hist		= require "histogram"
local memory	= require "memory"
local stats		= require "stats"
local timer		= require "timer"
local ffi		= require "ffi"

local PKT_SIZE = 60

local NUM_PKTS = 10^6

function master(txPort, rxPort, load)
	if not txPort or not rxPort or type(load) ~= "number" then
		errorf("usage: txPort rxPort load")
	end
	local txDev = device.config{port = txPort, rxQueues = 2, txQueues = 2}
	local rxDev = device.config{port = rxPort, rxQueues = 2, txQueues = 2}
	device.waitForLinks()
	txDev:getTxQueue(0):setRate(load)
	if load > 0 then mg.launchLua("loadSlave", txDev:getTxQueue(0)) end
	mg.launchLua("txTimestamper", txDev:getTxQueue(1))
	mg.launchLua("rxTimestamper", rxDev:getRxQueue(1))
	mg.waitForSlaves()
end

function loadSlave(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthPacket():fill{
		}
	end)
	local bufs = mem:bufArray()
	local ctr = stats:newDevTxCounter("Load Traffic", queue.dev, "plain")
	while mg.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		ctr:update()
	end
	ctr:finalize()
end

function txTimestamper(queue)
	local mem = memory.createMemPool(function(buf)
		-- just to use the default filter here
		-- you can use whatever packet type you want
		buf:getUdpPtpPacket():fill{
		}
	end)
	mg.sleepMillis(1000) -- ensure that the load task is running
	local bufs = mem:bufArray(1)
	local rateLimit = timer:new(0.0001) -- 10kpps timestamped packets
	local i = 0
	while i < NUM_PKTS and mg.running() do
		bufs:alloc(PKT_SIZE)
		queue:sendWithTimestamp(bufs)
		rateLimit:wait()
		rateLimit:reset()
		i = i + 1
	end
	mg.sleepMillis(500)
	mg.stop()
end

-- FIXME: the API should be nicer
function rxTimestamper(queue)
	local tscFreq = mg.getCyclesFrequency()
	local timestamps = ffi.new("uint64_t[64]")
	local bufs = memory.bufArray(64)
	-- use whatever filter appropriate for your packet type
	queue.dev:filterTimestamps(queue)
	local results = {}
	local rxts = {}
	while mg.running() do
		local numPkts = queue:recvWithTimestamps(bufs, timestamps)
		for i = 1, numPkts do
			local rxTs = timestamps[i - 1]
			local txTs = bufs[i]:getSoftwareTxTimestamp()
			results[#results + 1] = tonumber(rxTs - txTs) / tscFreq * 10^9 -- to nanoseconds
			rxts[#rxts + 1] = tonumber(rxTs)
		end
		bufs:free(numPkts)
	end
	local f = io.open("pings.txt", "w+")
	for i, v in ipairs(results) do
		f:write(v .. "\n")
	end
	f:close()
end

