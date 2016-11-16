local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local ts     = require "timestamping"
local stats  = require "stats"
local hist   = require "histogram"
local lacp   = require "proto.lacp"

local PKT_SIZE      = 60
local ETH_DST       = "90:E2:BA:C0:EE:8C"
local SRC_IP        = "10.10.10.1"
local DST_IP        = "10.10.10.2"
local SRC_PORT_BASE = 3000 -- + NIC id 
local DST_PORT_BASE = 4000 -- + count(NUM_FLOWS)
local NUM_FLOWS		= 100 -- per port

function master(...)
	if select("#", ...) < 2 then
		return print("usage: port [ports...] ratePerPort")
	end
	local rate = select(select("#", ...), ...)
	local ports = { ... }
	ports[#ports] = nil
	rate = rate or 10000
	local lacpQueues = {}
	local pingQueues = {}
	for i = 1, select("#", ...) - 1 do
		local port = device.config{port = ports[i], rxQueues = 3, txQueues = 3} 
		lacpQueues[#lacpQueues + 1] = {rxQueue = port:getRxQueue(1), txQueue = port:getTxQueue(1)}
		pingQueues[#pingQueues + 1] = {rx = port:getRxQueue(2), tx = port:getTxQueue(2)}
		ports[i] = port
	end
	device.waitForLinks()
	lacp.startLacpTask("bond0", lacpQueues)
	lacp.waitForLink("bond0")
	local lacpSource = lacp.getMac("bond0")
	for i, port in ipairs(ports) do 
		local queue = port:getTxQueue(0)
		queue:setRate(rate)
		mg.startTask("loadSlave", queue, lacpSource)
	end
	--mg.startTask("timerSlave", pingQueues, lacpSource)
	mg.waitForTasks()
end

local function fillPacket(buf, srcMac, qid, size)
	buf:getUdpPacket():fill{
		ethSrc = srcMac,
		ethDst = ETH_DST,
		ip4Src = SRC_IP,
		ip4Dst = DST_IP,
		udpSrc = SRC_PORT_BASE + qid,
		pktLength = size or PKT_SIZE
	}
end

function loadSlave(queue, lacpSource)
	local mem = memory.createMemPool(function(buf)
		fillPacket(buf, lacpSource, queue.id)
	end)
	local bufs = mem:bufArray()
	local txCtr = stats:newDevTxCounter(queue.dev, "plain")
	local rxCtr = stats:newDevRxCounter(queue.dev, "plain")
	local counter = 0
	while mg.running() do
		bufs:alloc(PKT_SIZE)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.udp:setDstPort(DST_PORT_BASE + counter)
			counter = incAndWrap(counter, NUM_FLOWS)
		end
		bufs:offloadUdpChecksums()
		--bufs:setVlans(1234)
		queue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
end

-- FIXME: this obviously loses all pakets that arrive on the wrong lacp member
function timerSlave(queues, lacpSource)
	local timestampers = {}
	for i, queue in ipairs(queues) do
		timestampers[#timestampers + 1] = ts:newUdpTimestamper(queue.tx, queue.rx)
	end
	local hist = hist:new()
	mg.sleepMillis(1000) -- ensure that the load task is running
	local size = math.max(84, PKT_SIZE)
	local counter = 0
	while mg.running() do
		for i, queue in ipairs(queues) do
			local timestamper = timestampers[i]
			local lat = timestamper:measureLatency(size, function(buf)
				fillPacket(buf, lacpSource, queue.tx.id, size)
				local pkt = buf:getUdpPacket()
				pkt.udp:setSrcPort(DST_PORT_BASE + counter)
				pkt.ip4.dst:set(math.random(0, 2^32 - 1))--setDstPort(DST_PORT_BASE + counter)
				counter = incAndWrap(counter, NUM_FLOWS)
			end)
		--	hist:print()
		end
	end
	hist:print()
	hist:save(histfile)
end

