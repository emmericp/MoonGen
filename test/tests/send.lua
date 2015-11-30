EXPORT_ASSERT_TO_GLOBALS = true
local luaunit   = require('luaunit')

local dpdk	= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer 	= require "timer"

local PKT_SIZE  = 60 -- without CRC

TestSend = {}

    function master()
		local testPorts = { 10, 11 }
        local testDevs = {}
		for i, v in ipairs(testPorts) do
			testDevs[i] = device.config{ port = testPorts[i], rxQueues = 2, txQueues = 3}
		end
        device.waitForLinks()

		--for i, v in ipairs(testPorts) do
		for i = 1, #testPorts do
			TestSend["testNic" .. testPorts[i]] = function()
				luaunit.assertTrue( slave( testDevs[i] ) )
			end
		end
		os.exit( luaunit.LuaUnit.run() )
    end

    function slave(queue)
        print("Testing stuff: ", queue)
        dpdk.sleepMillis(100)
        local mem = memory.createMemPool(function(buf)
            buf:getEthernetPacket():fill{
                pktLength = PKT_SIZE,
                ethSrc = queue[1],
                ethDst = "10:11:12:13:14:15",
            }
        end)
        local bufs = mem:bufArray()
        local runtime = timer:new(10)
        while runtime:running() and dpdk.running() do
            bufs:alloc(size)
            queue:send(bufs)
            ctr:update()
        end
        return 1
    end


