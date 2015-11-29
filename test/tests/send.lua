EXPORT_ASSERT_TO_GLOBALS = true
local luaunit   = require('luaunit')

local dpdk		= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"

local PKT_SIZE  = 60 -- without CRC
local ETH_DST	= "10:11:12:13:14:15" -- src mac is taken from the NIC
local IP_SRC	= "192.168.0.1"
local NUM_FLOWS	= 256 -- src ip will be IP_SRC + random(0, NUM_FLOWS - 1)
local IP_DST	= "10.0.0.1"
local PORT_SRC	= 1234


local txDev, rxDev
local rate = 100


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
				slave(testDevs[i])
			end
		end

		os.exit( luaunit.LuaUnit.run() )
    end

    function slave(queue, port)
		print("Testing stuff: ", queue)
		luaunit.assertTrue(false)
		--do return true end
        dpdk.sleepMillis(100)
        local mem = memory.createMemPool(function(buf)
            buf:getUdpPacket():fill{
                pktLength = PKT_SIZE,
                ethSrc = queue,
                ethDst = ETH_DST,
                ip4Dst = IP_DST,
                udpSrc = PORT_SRC,
                udpDst = port
            }
        end)
    
        local txCtr = stats:newManualTxCounter("Port " .. port, "plain")
        local baseIP = parseIPAddress(IP_SRC)
        local bufs = mem:bufArray()
    
        while dpdk.running() do
            bufs:alloc(PKT_SIZE)
        
            for _, buf in ipairs(bufs) do
                local pkt = buf:getUdpPacket()
                pkt.ip4.src:set(baseIP + math.random(NUM_FLOWS) - 1)
            end
        
            bufs:offloadUdpChecksums()
            txCtr:updateWithSize(queue:send(bufs), PKT_SIZE)
        end
    
        txCtr:finalize()
    end


