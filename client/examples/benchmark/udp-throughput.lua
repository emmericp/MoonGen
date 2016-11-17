local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local stats  = require "stats"

local PKT_SIZE	= 60

function master(...)
	local devices = { ... }
	if #devices == 0 then
		return print("Usage: port[:numcores] [port:[numcores] ...]")
	end
	for i, v in ipairs(devices) do
		local id, cores
		if type(v) == "string" then
			id, cores = tonumberall(v:match("(%d+):(%d+)"))
		else
			id, cores = v, 1
		end
		if not id or not cores then
			print("could not parse " .. tostring(v))
			return
		end
		devices[i] = { device.config{ port = id, txQueues = cores }, cores }
	end
	device.waitForLinks()
	for i, dev in ipairs(devices) do
		local dev, cores = unpack(dev)
		for i = 1, cores do
			mg.startTask("loadSlave", dev, dev:getTxQueue(i - 1), 256, i == 1)
		end
	end
	mg.waitForTasks()
end


function loadSlave(dev, queue, numFlows, showStats)
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = "10:11:12:13:14:15",
			ip4Dst = "192.168.1.1",
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	while mg.running() do
		bufs:alloc(PKT_SIZE)
		for _, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.ip4.src:set(baseIP + flow)
			flow = incAndWrap(flow, numFlows)
		end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		queue:send(bufs)
		if showStats then ctr:update() end
	end
	if showStats then ctr:finalize() end
end

