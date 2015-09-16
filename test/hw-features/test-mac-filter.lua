local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log		= require "log"

local PKT_SIZE	= 60

function master(loadPort, dutPort)
	if not loadPort or not dutPort then
		return print("usage: loadPort dutPort")
	end
	local loadDev = device.config{ port = loadPort }
	local dutDev = device.config{ port = dutPort }
	dutDev:setPromisc(false)
	device.waitForLinks()
	dpdk.launchLua("loadSlave", loadDev:getTxQueue(0))
	dpdk.launchLua("dutSlave", dutDev:getRxQueue(0), dutDev)
	dpdk.waitForSlaves()
end


function loadSlave(txQueue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket().eth:setSrcString("01:02:03:04:05:06")
	end)
	local bufs = mem:bufArray()
	local counter = 0
	local txCtr = stats:newDevTxCounter(txQueue, "plain")
	-- FIXME: second argument should be set by default and the old representation needs to be deprecated
	local baseMac = parseMacAddress("01:02:03:04:00:00", true)
	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		for i, buf in ipairs(bufs) do
			-- FIXME: mac addresses should support intuitive arithmetic...
			buf:getEthernetPacket().eth:setDst(bit.bswap(bit.bswap(baseMac + 0ULL) + bit.lshift(counter, 16)))
			counter = incAndWrap(counter, 4095)
		end
		txQueue:send(bufs)
		txCtr:update()
	end
	txCtr:finalize()
end

local testMacs = {
	"01:02:03:04:00:05",
	"01:02:03:04:01:13",
	"01:02:03:04:02:55"
}

function dutSlave(rxQueue, dev)
	dev:addMac("01:02:03:05:03:11")
	dev:removeMac("01:02:03:05:03:11")
	local whitelist = {}
	for _, mac in ipairs(testMacs) do
		whitelist[parseMacAddress(mac, true)] = 0
		dev:addMac(mac)
	end
	local bufs = memory.bufArray()
	while dpdk.running() do
		local rx = rxQueue:tryRecv(bufs, 10)
		for i = 1, rx do
			local buf = bufs[i]
			local pkt = buf:getEthernetPacket()
			local dst = pkt.eth:getDst()
			if whitelist[dst] then
				whitelist[dst] = whitelist[dst] + 1
			else
				log:fatal("received unexpected MAC: %s", pkt.eth:getDstString())
			end
		end
		bufs:free(rx)
	end
	for mac, hits in pairs(whitelist) do
		if hits == 0 then
			log:warn("received 0 packets for dst mac: %012X", mac)
		else
			log:info("%012X: %d packets", mac, hits)
		end
	end
end
