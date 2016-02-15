-- Start MoonGen and send some packages from each card to the network.
-- Check all cards if they received packets from the broadcasting card.

local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local tconfig	= require "tconfig"

--memory.enableCache()
local PKT_SIZE	= 100

function master()
	local cards = tconfig.cards()
	local devs = {}
	for i=1, #cards do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()
	for i=1, #devs do
		broadcastSlave(devs[i])
		dpdk.sleepMillis( 100 )
		for j=1, #devs do
			receiveSlave(devs[j],cards[j])
		end
		--slave:wait()
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
				print(lmac, " - ", card[2])
			end
		end
		bufs:free(rx)
	end
end
