local dpdk   = require "dpdk"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"

function master(txPort)
	if not txPort then
		errorf("usage: txPort")
	end
	local txDev = device.config(txPort)
	txDev:wait()
	stats.startStatsTask({txDev})
	dpdk.launchLua("burstGenSlave", txPort, 10, 1000, 2 * 10^6, 0.1 * 10^6)
	dpdk.sleepMillis(100) -- make sure the burst thread starts first
	dpdk.launchLua("loadSlave", txPort, 0)
	dpdk.waitForSlaves()
end

function burstGenSlave(port, rate, burstRate, time, burstTime)
	local queue = device.get(port):getTxQueue(0)
	-- it might be a good idea to move the following into a C function as the JIT could interfere with the timing here
	-- however, initial tests showed no problems (probably because of the extremely small size of the running code)
	while dpdk.running() do
		queue:setRate(rate)
		dpdk.sleepMicros(time)
		queue:setRate(burstRate)
		dpdk.sleepMicros(burstTime)
	end
end

function loadSlave(port, queue)
	local queue = device.get(port):getTxQueue(queue)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill()
	end)
	local bufs = mem:bufArray()
	while dpdk.running() do
		bufs:alloc(60)
		queue:send(bufs)
	end
end

