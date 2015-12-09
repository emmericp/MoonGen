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
		slave = dpdk.launchLua("broadcastSlave", devs[i], cards[i][1])
		for j=1, #devs do
			receiveSlave(devs[j])
		end
		slave:wait()
	end
end

function broadcastSlave(dev, port)
	local queue = dev:getTxQueue(0)
	
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray()
	while dpdk.running() do
		-- Send
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
	end
	bufs:freeAll()
end

function receiveSlave(dev)
	dpdk.sleepMillis(100)
	local queue = dev:getRxQueue(0)
	local bufs = memory.bufArray()
	runtime = timer:new(0.001)
	while runtime:running() and dpdk.running() do
		--receive
		maxWait = 1000
		local rx = queue:tryRecv(bufs, maxWait)
		for i=1, rx do
			local buf = bufs[i]
			local pkt = buf:getUdpPacket()
			print(pkt)
			--local port = pkt.udp:getDstPort()
			--print(port)
		end
		--local buf = bufs[1]
		--local pkt = buf:getEthernetPacket()
		--local port = pkt:getDstPort()
		--print(port)
	end
	bufs:freeAll()
end
	
