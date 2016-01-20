local luaunit	= require "luaunit"
local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local tconfig	= require "tconfig"

Tests = {}

--memory.enableCache()
local PKT_SIZE	= 100

function master()
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()

	local devs = {}
	for i=1, #pairs, 2 do
		devs[i] = device.config{ port = cards[pairs[i][1]+1][1], rxQueues = 2, txQueues = 3}
		devs[i+1] = device.config{ port = cards[pairs[i][2]+1][1], rqQueue = 2, txQueue = 3}
	end
	device.waitForLinks()
	for i=1, #devs,2 do
		Tests["testNic" .. i] = function()
			local sent1 = sendSlave(devs[i+1]:getTxQueue(0))
			luaunit.assertTrue(receiveSlave(devs[i]:getRxQueue(0), sent1))
		end
		Tests["testNic" .. i+1] = function ()
			local sent2 = sendSlave(devs[i]:getTxQueue(0))
			luaunit.assertTrue(receiveSlave(devs[i+1]:getRxQueue(0), sent2))
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

function sendSlave(queue)
	dpdk.sleepMillis(100)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mem:bufArray(1)

	local i = 0
	local max = 100
	local runtime = timer:new(1)
	while dpdk.running() and runtime:running() and i < max do
		-- Send
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		i = i + 1
	end
	-- print(i)
	return i
end

function receiveSlave(queue, sent)
	dpdk.sleepMillis(100)
	local bufs = memory.bufArray()
	runtime = timer:new(1)
	local packets = 0
	while runtime:running() and dpdk.running() do
		--receive
		maxWait = 1
		local rx = queue:tryRecv(bufs, maxWait)
		for i=1, rx do
			-- local buf = bufs[i]
			-- local pkt = buf:getEthernetPacket()
			packets = packets + 1
		end
		bufs:free(rx)
	end
	return packets >= sent
end
