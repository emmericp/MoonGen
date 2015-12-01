local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local stats		= require "stats"
local hist		= require "histogram"
local log		= require "log"

local PKT_SIZE	= 124
local ETH_DST	= "11:12:13:14:15:16"

function master(txPort, rate, rc)
	if not txPort or not rate or not rc then
		return print("usage: txPort rate hw|sw|moongen")
	end
	rate = rate or 2
	local txDev = device.config{ port = txPort }
	device.waitForLinks()
	local queue = txDev:getTxQueue(0)
	dpdk.launchLua("loadSlave", queue, txDev, rate, rc)
	dpdk.waitForSlaves()
end

function loadSlave(queue, txDev, rate, rc)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txCtr
	if rc == "hw" then
		txCtr = stats:newDevTxCounter(txDev, "plain")
		queue:setRate(rate * (PKT_SIZE + 4) * 8)
		dpdk.sleepMillis(100) -- for good meaasure
		while dpdk.running() do
			bufs:alloc(PKT_SIZE)
			queue:send(bufs)
			txCtr:update()
		end
	elseif rc == "sw" then
		log:error("NYI")
	elseif rc == "moongen" then
		txCtr = stats:newManualTxCounter(txDev, "plain")
		while dpdk.running() do
			bufs:alloc(PKT_SIZE)
			for _, buf in ipairs(bufs) do
				buf:setDelay(10^10 / 8 / (rate * 10^6) - PKT_SIZE - 24)
			end
			txCtr:updateWithSize(queue:sendWithDelay(bufs), PKT_SIZE)
		end
	else
		log:error("Unknown rate control method")
	end
	txCtr:finalize()
end

