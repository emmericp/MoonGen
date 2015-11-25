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

    function master()
        local txPort = 7;
        local rxPort = 11;
        local rate = 100;
        
        local txDev = device.config{ port = txPort, rxQueues = 2, txQueues = 3}
        local rxDev = device.config{ port = rxPort, rxQueues = 2, txQueues = 3}
    
        device.waitForLinks()
        dpdk.launchLua("slave", txDev, rxDev, txDev:getTxQueue(0), rate, PKT_SIZE)
        dpdk.waitForSlaves()
    end

    function slave(queue, port)
        mg.sleepMillis(100)
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
    
        while mg.running() do
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

function testSend()
    f = master()
    luaunit.assertIsFunction(f)
end

os.exit( luaunit.LuaUnit.run() )