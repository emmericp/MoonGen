--- Replay a pcap file.

local mg     = require "moongen"
local device = require "device"
local memory = require "memory"
local stats  = require "stats"
local log    = require "log"
local pcap   = require "pcap"

function configure(parser)
	parser:argument("dev", "Device to use."):args(1):convert(tonumber)
	parser:argument("file", "File to replay."):args(1)
	parser:option("-r --rate-multiplier", "Speed up or slow down replay, 1 = use intervals from file, default = replay as fast as possible"):default(0):convert(tonumber):target("rateMultiplier")
	parser:flag("-l --loop", "Repeat pcap file.")
	local args = parser:parse()
	if args.rateMultiplier ~= 0 then
		parser:error("rate control is NYI")
	end
	return args
end

function master(args)
	local dev = device.config{port = args.dev}
	device.waitForLinks()
	mg.startTask("replay", dev:getTxQueue(0), args.file, args.loop)
	stats.startStatsTask{txDevices = {dev}}
	mg.waitForTasks()
end

function replay(queue, file, loop)
	local mempool = memory:createMemPool()
	local bufs = mempool:bufArray()
	local pcapFile = pcap:newReader(file)
	while mg.running() do
		local n = pcapFile:read(bufs)
		if n == 0 then
			if loop then
				pcapFile:reset()
			else
				break
			end
		end
		queue:sendN(bufs, n)
	end
end

