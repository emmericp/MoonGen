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
	local testPorts = tconfig.ports()
    
        local testDevs = {}
		for i, v in ipairs(testPorts) do
			testDevs[i] = device.config{ port = testPorts[i], rxQueues = 2, txQueues = 3}
		end
        device.waitForLinks()

		for i = 1, #testPorts do
			TestSend["testNic" .. testPorts[i]] = function()
				luaunit.assertTrue( slave( testDevs[i] ) )
			end
		end
		os.exit( luaunit.LuaUnit.run() )
    end

    function slave(dev)
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
        local runtime = timer:new(10)
        while runtime:running() and dpdk.running() do
            bufs:alloc(PKT_SIZE)
            queue:send(bufs)
        end
    
        return 1 -- Test Successful
    end


