--- Replay a pcap file.

local mg      = require "moongen"
local device  = require "device"
local memory  = require "memory"
local stats   = require "stats"
local log     = require "log"
local pcap    = require "pcap"
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
	local rateLimiter
	if args.rateMultiplier > 0 then
		rateLimiter = limiter:new(dev:getTxQueue(0), "custom")
	end
	mg.startTask("replay", dev:getTxQueue(0), args.file, args.loop, rateLimiter, args.rateMultiplier)
	stats.startStatsTask{txDevices = {dev}}
	mg.waitForTasks()
end

function replay(queue, file, loop, rateLimiter, multiplier)
	local mempool = memory:createMemPool(4096)
	local bufs = mempool:bufArray()
	local pcapFile = pcap:newReader(file)
	local prev = 0
	local linkSpeed = queue.dev:getLinkStatus().speed
	while mg.running() do
		local n = pcapFile:read(bufs)
		if n > 0 then
			if rateLimiter ~= nil then
				if prev == 0 then
					prev = bufs.array[0].udata64
				end
				for i, buf in ipairs(bufs) do
					-- ts is in microseconds
					local ts = buf.udata64
					local delay = ts - prev
					delay = tonumber(delay * 10^3) / multiplier -- nanoseconds
					delay = delay / (8000 / linkSpeed) -- delay in bytes
					buf:setDelay(delay)
					prev = ts
				end
			end
		else
			if loop then
				pcapFile:reset()
			else
				break
			end
		end
		if rateLimiter then
			rateLimiter:sendN(bufs, n)
		else
			queue:sendN(bufs, n)
		end
	end
end

