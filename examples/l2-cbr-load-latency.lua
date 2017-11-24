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
end

function master(args)
	local txDev = device.config({port = args.txDev, txQueues = 2, rxQueues = 2})
	local rxDev = device.config({port = args.rxDev, txQueues = 2, rxQueues = 2})
	PKT_SIZE = math.max(60, tonumber(args.size))
	print("using packet size "..PKT_SIZE)
	device.waitForLinks()
	mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(0), args.rate, PKT_SIZE)
	mg.startTask("timerSlave", txDev:getTxQueue(1), rxDev:getRxQueue(1), PKT_SIZE)
	mg.waitForTasks()
end

function loadSlave(dev, rxDev, queue, rate, size)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local rxStats = stats:newDevRxCounter(rxDev, "plain")
	local txStats = stats:newManualTxCounter(dev, "plain")
	while mg.running() do
		bufs:alloc(size)
		for _, buf in ipairs(bufs) do
			-- this script uses Mpps instead of Mbit (like the other scripts)
			--buf:setDelay((10^10 / 8 / (rate * 10^6) - size - 24))
			buf:setDelay((size+24) * (1000/rate - 1) )
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

function timerSlave(txQueue, rxQueue, size)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = histogram:new()
	-- wait for a second to give the other task a chance to start
	mg.sleepMillis(1000)
	local rateLimiter = timer:new(0.001)
	while mg.running() do
		rateLimiter:reset()
		hist:update(timestamper:measureLatency(size))
		rateLimiter:busyWait()
	end
	hist:print()
	hist:save("histogram.csv")
end

