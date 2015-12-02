EXPORT_ASSERT_TO_GLOBALS = true

local luaunit   = require "luaunit"
local dpdk      = require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer 	= require "timer"

package.path 	= package.path .. ";../tconfig.lua"
local tconfig   = require "tconfig"

local PKT_SIZE  = 60 -- without CRC

TestSend = {}

    function master()
        local testPairs = tconfig.pairs()
    
        local testPorts = {}
        for i = 1, #testPairs do
        	testPorts[i*2-1] = testPairs[i][1]
        	testPorts[i*2] = testPairs[i][2]
	end
    
        local testDevs = {}
	for i, v in ipairs(testPorts) do
		testDevs[i] = device.config{ port = testPorts[i], rxQueues = 2, txQueues = 3}
	end
        device.waitForLinks()

	for i = 1, #testDevs, 2 do
		TestSend["testNic" .. testPorts[i] .. " " .. testPorts[i+1]] = function()
			sendSlave( testDevs[i], testDevs[i+1] )
			luaunit.assertTrue( receiveSlave( testDevs[i+1] ) )
			sendSlave( testDevs[i+1], testDevs[i] )
			luaunit.assertTrue( receiveSlave( testDevs[i] ) )
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
        while runtime:running() and dpdk.running() do
            bufs:alloc(PKT_SIZE)
            queue:send(bufs)
        end
    
        return 1
    end

    function receiveSlave(dev)
        print("Testing Receive Capability: ", dev)
    
        local queue = dev:getTxQueue(1)
        while dpdk.running(100) do
            queue:recv(bufs)
        end
    
        return 1 -- Test Successful
    end


