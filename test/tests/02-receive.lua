EXPORT_ASSERT_TO_GLOBALS = true

local luaunit   = require "luaunit"
local dpdk      = require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer 	= require "timer"

local tconfig   = dofile("config/tconfig.lua")

local PKT_SIZE  = 60 -- without CRC

TestSend = {}

function master()
	local pairs = tconfig.pairs()
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
			local packages = sendSlave( devs[i], devs[i+1] )
			luaunit.assertTrue( receiveSlave( testDevs[i+1], packages ) )
			packages = sendSlave( devs[i+1], devs[i] )
			luaunit.assertTrue( receiveSlave( testDevs[i], packages ) )
		end
	end
	os.exit( luaunit.LuaUnit.run() )
    end

function sendSlave(dev, target)
        local queue = dev:getTxQueue(0)
        local tqueue = target:getTxQueue(0)
        dpdk.sleepMillis(100)
    
        local mem = memory.createMemPool(function(buf)
            buf:getEthernetPacket():fill{
                pktLength = PKT_SIZE,
                ethSrc = queue, --random src
                ethDst = tqueue, --random dst
            }
        end)
    
        local bufs = mem:bufArray()
        local runtime = timer:new(10)
	local i = 0
        while runtime:running() and dpdk.running() do
        	bufs:alloc(PKT_SIZE)
       		queue:send(bufs)
		i = i + 1
        end
 
        return i
end

function receiveSlave(dev, packages)
        print("Testing Receive Capability: ", dev)
	
	local bufs = memory.bufArray()    
        local queue = dev:getRxQueue(1)
	local runtime = timer:new(10)
        while runtime:running() and dpdk.running() do
            queue:tryRecv(bufs, 100)
        end
	
        return 1 -- Test Successful
end
