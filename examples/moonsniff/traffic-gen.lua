--- Demonstrates and tests hardware timestamping capabilities

local lm     = require "libmoon"
local device = require "device"
local memory = require "memory"
local ts     = require "timestamping"
local hist   = require "histogram"
local timer  = require "timer"
local log    = require "log"
local stats  = require "stats"

local RUN_TIME = 100            -- in seconds
local SEND_RATE = 1000          -- in mbit/s
local PKT_LEN = 100             -- in byte

function configure(parser)
        parser:description("Generate traffic which can be used by moonsniff to establish latencies induced by a device under test.")
        parser:argument("dev", "Devices to use."):args(2):convert(tonumber)
        return parser:parse()
end

function master(args)
        args.dev[1] = device.config{port = args.dev[1], txQueues = 1}
        args.dev[2] = device.config{port = args.dev[2], rxQueues = 1}
        device.waitForLinks()
        local dev0tx = args.dev[1]:getTxQueue(0)
        local dev1rx = args.dev[2]:getRxQueue(0)

        stats.startStatsTask{txDevices = {args.dev[1]}, rxDevices = {args.dev[2]}}

        local sender0 = lm.startTask("generateTraffic", dev0tx)

        sender0:wait()
end

function generateTraffic(queue)
        log:info("Trying to enable rx timestamping of all packets, this isn't supported by most nics")
        local pkt_id = 0
        local runtime = timer:new(RUN_TIME)
        local hist = hist:new()
        local mempool = memory.createMemPool(function(buf)
                buf:getUdpPacket():fill{
                        pktLength = PKT_LEN;
                }
        end)
        local bufs = mempool:bufArray()
        if lm.running() then
                lm.sleepMillis(500)
        end
        log:info("Trying to generate ~" .. SEND_RATE .. " mbit/s")
        queue:setRate(SEND_RATE)
        local runtime = timer:new(RUN_TIME)
        while lm.running() and runtime:running() do
                bufs:alloc(PKT_LEN)

                for i, buf in ipairs(bufs) do
                        local pkt = buf:getUdpPacket()
                        pkt.payload.uint32[0] = pkt_id
                        pkt_id = pkt_id + 1
                end

               queue:send(bufs)
        end
end
