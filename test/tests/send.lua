EXPORT_ASSERT_TO_GLOBALS = true
local luaunit   = require('luaunit')

local mg		= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local filter	= require "filter"
local stats		= require "stats"
local hist		= require "histogram"
local timer		= require "timer"
local log		= require "log"

local PKT_SIZE  = 60 -- without CRC
local ETH_DST	= "10:11:12:13:14:15" -- src mac is taken from the NIC
local IP_SRC	= "192.168.0.1"
local NUM_FLOWS	= 256 -- src ip will be IP_SRC + random(0, NUM_FLOWS - 1)
local IP_DST	= "10.0.0.1"
local PORT_SRC	= 1234
local PORT_FG	= 42
local PORT_BG	= 43

    function master()
        local txPort = 13;
        local rxPort = 14;
        local rate = 100;

        local txDev = device.config(txPort, 2, 2)
        local rxDev = device.config(rxPort, 2, 2)
        device.waitForLinks()
        dpdk.launchLua("slave", txDev, rxDev, txDev:getTxQueue(0), rate, PKT_SIZE)
        dpdk.waitForSlaves()
        assertEquals(1,2)
    end

    function slave(queue, port)
        mg.sleepMillis(100) -- wait a few milliseconds to ensure that the rx thread is running
        -- TODO: implement barriers
        local mem = memory.createMemPool(function(buf)
            buf:getUdpPacket():fill{
                pktLength = PKT_SIZE, -- this sets all length headers fields in all used protocols
                ethSrc = queue, -- get the src mac from the device
                ethDst = ETH_DST,
                -- ipSrc will be set later as it varies
                ip4Dst = IP_DST,
                udpSrc = PORT_SRC,
                udpDst = port,
                -- payload will be initialized to 0x00 as new memory pools are initially empty
            }
        end)
        -- TODO: fix per-queue stats counters to use the statistics registers here
        local txCtr = stats:newManualTxCounter("Port " .. port, "plain")
        local baseIP = parseIPAddress(IP_SRC)
        -- a buf array is essentially a very thing wrapper around a rte_mbuf*[], i.e. an array of pointers to packet buffers
        local bufs = mem:bufArray()
        while mg.running() do
            -- allocate buffers from the mem pool and store them in this array
            bufs:alloc(PKT_SIZE)
            for _, buf in ipairs(bufs) do
                -- modify some fields here
                local pkt = buf:getUdpPacket()
                -- select a randomized source IP address
                -- you can also use a wrapping counter instead of random
                pkt.ip4.src:set(baseIP + math.random(NUM_FLOWS) - 1)
                -- you can modify other fields here (e.g. different source ports or destination addresses)
            end
            -- send packets
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