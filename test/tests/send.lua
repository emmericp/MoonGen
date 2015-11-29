EXPORT_ASSERT_TO_GLOBALS = true
local luaunit   = require('luaunit')

local dpdk		= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"

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
        print("Testing stuff: ", testDevs)
        dpdk.sleepMillis(100)
        local mem = memory.createMemPool(function(buf)
            buf:getEthernetPacket():fill{
                pktLength = PKT_SIZE,
                ethSrc = queue,
                ethDst = "10:11:12:13:14:15",
            }
        end)
        local bufs = mem:bufArray()
        local ctr = stats:newDevTxCounter(queue[1], "plain")
        local runtime = timer:new(10)
        while runtime:running() and dpdk.running() do
            bufs:alloc(size)
            queue:send(bufs)
            ctr:update()
        end
        ctr:finalize()
        return 1
    end


