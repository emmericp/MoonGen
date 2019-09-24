local mg        = require "moongen"
local memory    = require "memory"
local ts        = require "timestamping"
local device    = require "device"
local stats     = require "stats"
local timer     = require "timer"
local histogram = require "histogram"
local log       = require "log"

local PKT_SIZE = 60

function configure(parser)
	parser:description("Generates traffic based on a poisson process with CRC-based rate control.")
	parser:argument("txDev", "Device to transmit from."):args(1):convert(tonumber)
	parser:argument("rxDev", "Device to receive from."):args(1):convert(tonumber)
	parser:option("-r --rate", "Transmit rate in Mpps."):args(1):default(2)
	parser:option("-s --size", "Packet size to use (min=60, max~~1500)"):args(1):default(60)
	parser:option("-n --numpackets", "Number of packets to sample (default = 0 = run forever)"):args(1):default(0):convert(tonumber)
	parser:option("-w --maxwait", "Max time (in ms) to wait got timer packets to come back (default=100)"):args(1):default(100):convert(tonumber)
end

function master(args)
	local txDev = device.config({port = args.txDev, txQueues = 2, rxQueues = 2})
	local rxDev = device.config({port = args.rxDev, txQueues = 2, rxQueues = 2})
	PKT_SIZE = math.max(60, tonumber(args.size))
	print("using packet size "..PKT_SIZE)
	device.waitForLinks()
	
	mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(0), args.rate, PKT_SIZE)
	mg.startTask("timerSlave", txDev:getTxQueue(1), rxDev:getRxQueue(1), PKT_SIZE, args.numpackets, args.maxwait)
	mg.waitForTasks()
end

function loadSlave(txDev, rxDev, queue, rate, size)
	
	-- doing crc rate control requires us to know the link speed.
	-- it is given in Mbps, just like the rate argument
	local linkspeed = txDev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)
	
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local rxStats = stats:newDevRxCounter(rxDev, "plain")
	local txStats = stats:newManualTxCounter(txDev, "plain")
	while mg.running() do
		bufs:alloc(size)
		for _, buf in ipairs(bufs) do
			-- this script uses Mpps instead of Mbit (like the other scripts)
			--buf:setDelay((10^10 / 8 / (rate * 10^6) - size - 24))
			buf:setDelay((size+24) * (linkspeed/rate - 1) )
			--buf:setRate(rate*10)  -- rate in Mpps on gigabit ethernet
			-- from crc-ratecontrol.lua:
			--   delay The time to wait before this packet \(in bytes, i.e. 1 == 0.8 nanoseconds on 10 GbE\)
			--   self.udata64 = 10^10 / 8 / (rate * 10^6) - self.pkt_len - 24
			-- key code from stats.lua (accounting for preamble + inter-packet gap = 8+12?): 
			-- 	local mpps = (pkts - self.total) / elapsed / 10^6
			-- 	local mbit = (bytes - self.totalBytes) / elapsed / 10^6 * 8
			-- 	local wireRate = mbit + (mpps * 20 * 8)
		end
		txStats:updateWithSize(queue:sendWithDelay(bufs), size)
		rxStats:update()
		--txStats:update()
	end
	rxStats:finalize()
	txStats:finalize()
end


-- in order to pass a maxWait parameter to timestamper:measureLatency we need
-- to also pass a packet modifying function.  This one does nothing.
function dummyModifier(buf)
	return false
end


function timerSlave(txQueue, rxQueue, size, numpackets, maxWait)
	numpackets = numpackets or 0
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = histogram:new()
	-- wait for a second to give the other task a chance to start
	mg.sleepMillis(1000)
	local rateLimiter = timer:new(0.001)
	local pktCount = 0
	while mg.running() and (numpackets == 0 or pktCount < numpackets) do
		rateLimiter:reset()
		local measurement, num = timestamper:measureLatency(size, dummyModifier, maxWait)
		--print(measurement, num)
		hist:update(measurement)
		pktCount = pktCount + 1
		rateLimiter:busyWait()
	end
	mg.stop()
	print("latency measurements: "..pktCount)
	hist:print()
	hist:save("histogram.csv")
end

