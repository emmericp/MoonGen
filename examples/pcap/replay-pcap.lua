--- Replay a pcap file.

local mg     = require "moongen"
local device = require "device"
local memory = require "memory"
local stats  = require "stats"
local log    = require "log"
local pcap   = require "pcap"
local limiter = require "software-ratecontrol"

function configure(parser)
	parser:argument("dev", "Device to use."):args(1):convert(tonumber)
    parser:argument("file", "File to replay."):args(1)
    parser:option("-r --rate-multiplier", "Speed up or slow down replay, 1 = use intervals from file, default = replay as fast as possible"):default(0):convert(tonumber):target("rateMultiplier")
    parser:flag("-l --loop", "Repeat pcap file.")
    local args = parser:parse()
    return args
end

function master(args)
	local dev = device.config{port = args.dev}
    device.waitForLinks()
    rateLimiter = nil
    if args.rateMultiplier == 1 then
        rateLimiter = limiter:new(dev:getTxQueue(0), "custom")
    end
    mg.startTask("replay", dev:getTxQueue(0), args.file, args.loop, rateLimiter)
    stats.startStatsTask{txDevices = {dev}}
    mg.waitForTasks()
end

function replay(queue, file, loop, rateLimiter)
	local mempool = memory:createMemPool()
    local bufs = mempool:bufArray()
    -- software-ratecontrol.lua#L29 For now it's mandatory to use a buffer of 1 position (lower or equal to the #packets in the pcap file)
    if rateLimiter ~= nil then
        bufs = mempool:bufArray(1)
    end
    local pcapFile = pcap:newReader(file)
    local prev = 0;
    while mg.running() do
        local n = pcapFile:read(bufs)
        if n > 0 then
            if rateLimiter ~= nil then
                if prev == 0 then
                    prev = (bufs.array[0].udata64 % 1000000) * 1000000 + math.floor(tonumber(bufs.array[0].udata64) / 1000000)
                end
                -- using pcap don't use ipairs (ipairs starts in 1 and C code in 0 - this produce index fails)
                for i=0, n-1 do
                    local cur = (bufs.array[i].udata64 % 1000000) * 1000000 + math.floor(tonumber(bufs.array[i].udata64) / 1000000)
                    bufs.array[i]:setDelay((cur-prev) * queue.dev:getLinkStatus().speed / 8)
                    prev = cur
                end
            end
        else
        	if loop then
            	pcapFile:reset()
        	else
            	break
        	end
    	end
    	if rateLimiter ~= nil then
            -- TODO: create sendN instead of send or solve software-ratecontrol.lua#L29
        	rateLimiter:send(bufs)
    	else
        	queue:sendN(bufs, n)
    	end
    end
end

