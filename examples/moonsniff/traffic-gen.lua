--- Generates MoonSniff traffic, i.e. packets contain an identifier and a fixed bit pattern
--- Live mode and MSCAP mode require this type of traffic

local lm     = require "libmoon"
local device = require "device"
local memory = require "memory"
local ts     = require "timestamping"
local hist   = require "histogram"
local timer  = require "timer"
local log    = require "log"
local stats  = require "stats"
local bit    = require "bit"

local PKT_LEN = 100 -- in byte
local MS_TYPE = 0b01010101
local band = bit.band

function configure(parser)
	parser:description("Generate traffic which can be used by moonsniff to establish latencies induced by a device under test.")
	parser:argument("dev", "Devices to use."):args(2):convert(tonumber)
	parser:option("-t --time", "Determines how long packets will be send in seconds."):args(1):convert(tonumber):default(10)
	parser:option("-r --rate", "Approximate send rate in mbit/s. Due to IFG etc. rate on the wire may be higher."):args(1):convert(tonumber):default(1000)
	return parser:parse()
end

function master(args)
	args.dev[1] = device.config { port = args.dev[1], txQueues = 1 }
	args.dev[2] = device.config { port = args.dev[2], rxQueues = 1 }
	device.waitForLinks()
	local dev0tx = args.dev[1]:getTxQueue(0)
	local dev1rx = args.dev[2]:getRxQueue(0)

	stats.startStatsTask { txDevices = { args.dev[1] }, rxDevices = { args.dev[2] } }

	local sender0 = lm.startTask("generateTraffic", dev0tx, args)

	sender0:wait()
	lm.stop()
	lm.waitForTasks()
end

function generateTraffic(queue, args)
	log:info("Trying to enable rx timestamping of all packets, this isn't supported by most nics")
	local pkt_id = 0
	local runtime = timer:new(args.time)
	local hist = hist:new()
	local mempool = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill {
			pktLength = PKT_LEN;
		}
	end)
	local bufs = mempool:bufArray()
	if lm.running() then
		lm.sleepMillis(500)
	end
	log:info("Trying to generate ~" .. args.rate .. " Mbit/s")
	queue:setRate(args.rate)
	local runtime = timer:new(args.time)
	while lm.running() and runtime:running() do
		bufs:alloc(PKT_LEN)

		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			-- for setters to work correctly, the number is not allowed to exceed 16 bit
			pkt.ip4:setID(band(pkt_id, 0xFFFF))
			pkt.payload.uint32[0] = pkt_id
			pkt.payload.uint8[4] = MS_TYPE
			pkt_id = pkt_id + 1
		end

		queue:send(bufs)
	end
end
