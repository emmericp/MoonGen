local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"
package.path 	= package.path .. ";tconfig.lua"
local tconfig	= require "tconfig"

local PKT_SIZE	= 100

function master()
	local cards = tconfig.cards()
	local devs = {}
	for i=1, #cards do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	for i=1, #devs do
		slave(devs[i])
		--dpdk.launchLua("slave", devs[i])
	end
end

function slave(dev)
	local txqueue = dev:getTxQueue(0)
	local rxqueue = dev:getRxQueue(0)
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txqueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray()
	local runtime = timer:new(0.0001)
	local count = 0
	while runtime:running() and dpdk.running() do
		-- Send
		bufs:alloc(PKT_SIZE)
		txqueue:send(bufs)

		-- Receive
		--local rx = rxqueue:tryRecv(bufs)
		
		--local buf = bufs[1]
		--local pkt = buf:getEthernetPacket()
		--local src = pkt:getDstPort()
	
		count = count + 1
		print(count)
	end
	bufs:freeAll()
end
	
