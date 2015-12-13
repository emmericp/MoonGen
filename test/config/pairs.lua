local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"
package.path 	= package.path .. ";tconfig.lua"
local tconfig	= require "tconfig"

memory.enableCache()
local PKT_SIZE	= 100

function master()
	local cards = tconfig.cards()
	local devs = {}
	for i=1, #cards do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	for i=1, #devs do
		slave = dpdk.launchLua("broadcastSlave", devs[i])
		for j=1, #devs do
			receiveSlave(devs[j],cards[j])
		end
		slave:wait()
	end
end

function broadcastSlave(dev)
	local queue = dev:getTxQueue(0)
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray()

	local i = 0
	local max = 1
	while dpdk.running() and i < max do
		-- Send
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		i = i + 1
	end
end

function receiveSlave(dev,card)
	dpdk.sleepMillis(100)
	local queue = dev:getRxQueue(0)
	local bufs = memory.bufArray()
	runtime = timer:new(0.001)
	local lmac = "NONE"
	while runtime:running() and dpdk.running() do
		--receive
		maxWait = 1000
		local rx = queue:tryRecv(bufs, maxWait)
		for i=1, rx do
			local buf = bufs[i]
			local pkt = buf:getEthernetPacket()
			local mac = pkt.eth:getSrcString()
			if not (mac == lmac) then
				lmac = mac
				print(card[2], " - ", lmac)
			end
		end
		bufs:free(rx)
	end
end
