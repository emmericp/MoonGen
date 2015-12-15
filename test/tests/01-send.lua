EXPORT_ASSERT_TO_GLOBALS = true

local luaunit   = require "luaunit"
local dpdk      = require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer 	= require "timer"

local tconfig   = dofile("../config/tconfig.lua")

local PKT_SIZE  = 1600 -- without CRC

TestSend = {}

function master()
	local cards = tconfig.cards()
    
        local devs = {}
		for i=1, #cards  do
			devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 3}
		end
		device.waitForLinks()

		for i = 1, #cards do
			TestSend["testNic" .. cards[i][1]] = function()
				luaunit.assertTrue( slave( devs[i], cards[i][3] ) )
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

function slave(dev, rate)
	print("Testing Send Capability: ", dev)

	local queue = dev:getTxQueue(0)
	dpdk.sleepMillis(100)
 
	local mem = memory.createMemPool(function(buf)
			buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = "10:11:12:13:14:15", --random src
				ethDst = "10:11:12:13:14:15", --random dst
			}
		end)
	
	local bufs = mem:bufArray()
	local runtime = timer:new(1)
	local i = 0
	while runtime:running() and dpdk.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		i = i + 1
	end

        return rate < i
end
