-- vim:ts=4:sw=4:noexpandtab
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"

local PKT_SIZE	= 60
local ETH_DST	= "11:12:13:14:15:16"

local function getRstFile(...)
       local args = { ... }
       for i, v in ipairs(args) do
               result, count = string.gsub(v, "%-%-result%=", "")
               if (count == 1) then
                       return i, result
               end
       end
       return nil, nil
end

function master(...)
	local rstindex, rstfile = getRstFile(...)
	if rstindex then
		histfile = rstfile
	else
		histfile = "histogram.csv"
	end

	local txPort, rxPort, rate = tonumberall(...)
	if not txPort or not rxPort then
		return print("usage: txPort rxPort [rate] [--result=filename]")
	end
	rate = rate or 10000
	-- hardware rate control fails with small packets at these rates
	local numQueues = rate > 6000 and rate < 10000 and 3 or 1
	local txDev = device.config(txPort, 2, 4)
	local rxDev = device.config(rxPort, 2, 4) -- ignored if txDev == rxDev
	device.waitForLinks()
	local queues1, queues2 = {}, {}
	for i = 1, numQueues do
		local queue = txDev:getTxQueue(i)
		queues1[#queues1 + 1] = queue
		if rate < 10000 then -- only set rate if necessary to work with devices that don't support hw rc
			queue:setRate(rate / numQueues)
		end
		local queue = rxDev:getTxQueue(i)
		queues2[#queues2 + 1] = queue
		if rate < 10000 then -- only set rate if necessary to work with devices that don't support hw rc
			queue:setRate(rate / numQueues)
		end
	end
	dpdk.launchLua("loadSlave", queues1, txDev, rxDev)
	if rxPort ~= txPort then
		dpdk.launchLua("loadSlave", queues2, rxDev, txDev)
	end
	dpdk.launchLua("timerSlave", txDev:getTxQueue(0), rxDev:getRxQueue(1), histfile)
	dpdk.waitForSlaves()
end

function loadSlave(queues, txDev, rxDev)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txCtr = stats:newDevTxCounter(txDev, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")
	while dpdk.running() do
		for i, queue in ipairs(queues) do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
		end
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

function timerSlave(txQueue, rxQueue, histfile)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(1000) -- ensure that the load task is running
	while dpdk.running() do
		hist:update(timestamper:measureLatency(function(buf) buf:getEthernetPacket().eth.dst:setString(ETH_DST) end))
	end
	hist:print()
	hist:save(histfile)
end

