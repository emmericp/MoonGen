EXPORT_ASSERT_TO_GLOBALS = true

local luaunit	= require "luaunit"
local dpdk	= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local tconfig	= require "tconfig"

local PKT_SIZE	= 124 -- without CRC

TestSend = {}

function master()
	local pairs = tconfig.pairs()
	local cards = tconfig.cards()

	local ports = {}
	for i = 1, #pairs do
		ports[i*2-1] = pairs[i][1]
		ports[i*2] = pairs[i][2]
	end
    
	local devs = {}
	for i=1, #ports do
		devs[i] = device.config{ port = ports[i], rxQueues = 2, txQueues = 3}
	end
	device.waitForLinks()

	for i = 1, #devs, 2 do
		TestSend["testNic" .. ports[i] .. " " .. ports[i+1]] = function()
			local packages = sendSlave( devs[i], cards[tonumber(ports[i+1])+1][2] )
			luaunit.assertTrue ( receiveSlave( devs[i+1], packages ) )
			packages = sendSlave( devs[i+1], cards[tonumber(ports[i])+1][2] )
			luaunit.assertTrue( receiveSlave( devs[i], packages ) )
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

function sendSlave(dev, target)
	local queue = dev:getTxQueue(0)
	dpdk.sleepMillis(100)

	print (dev)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = queue,
			ethDst = target
		}
	end)
	
	local bufs = mem:bufArray()
	local max = 1000
	local runtime = timer:new(0.01)
	local i = 0

	while runtime:running() and dpdk.running() and i < max do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		i = i + 1
	end

	return i
end

function receiveSlave(dev, packages)
	print(dev)
	dpdk.sleepMillis(100)

	local queue = dev:getRxQueue(0)
	local bufs = memory.bufArray()
	runtime = timer:new(0.01)
	local total = 0

	while runtime:running() and dpdk.running() do
		--receive
		maxWait = 100
		local rx = queue:tryRecv(bufs, maxWait)
		local i = 0
		while  i < rx do
			local buf = bufs[i]
			--local pkt = buf:getEthernetPacket()
			i = i + 1
		end
		total = total + i
		bufs:free(rx)
	end

	return total >= packages
end
