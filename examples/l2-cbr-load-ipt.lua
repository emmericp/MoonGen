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
	parser:option("-r --rate", "Transmit rate in Mpps."):args(1):default(2):convert(tonumber)
	parser:option("-s --size", "Packet size to use (min=60, max~~1500)"):args(1):default(60):convert(tonumber)
	parser:option("-n --numpackets", "Number of packets to sample (default = 0 = run forever)"):args(1):default(0):convert(tonumber)
end

function master(args)
	local txDev = device.config({port = args.txDev, txQueues = 2, rxQueues = 2})
	local rxDev = device.config({port = args.rxDev, rxDescs = 4096, dropEnable = false })
	PKT_SIZE = math.max(60, args.size)
	print("using packet size "..PKT_SIZE)
	device.waitForLinks()
	
	mg.startTask("iptSlave", rxDev:getRxQueue(0), args.numpackets)
	mg.startTask("loadSlave", txDev, txDev:getTxQueue(0), args.rate, PKT_SIZE)
	mg.waitForTasks()
end

function loadSlave(dev, queue, rate, size)
	
	-- doing crc rate control requires us to know the link speed.
	-- it is given in Mbps, just like the rate argument
	local linkspeed = dev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)
	
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txStats = stats:newManualTxCounter(dev, "plain")
	local numsent = 0
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
			
			numsent = numsent + 1
		end
		txStats:updateWithSize(queue:sendWithDelay(bufs), size)

	end
	print("sent packets:     "..numsent)
	txStats:finalize()
end

function iptSlave(queue, numpackets)
	queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray()
	local times = {}
	local numrx = 0
	while mg.running() and (numpackets == 0 or numrx < numpackets) do
		local n = queue:recv(bufs)
		for i = 1, n do
			local ts = bufs[i]:getTimestamp()
			times[#times + 1] = ts
			--print(ts)
			numrx = numrx + 1
		end
		total = total + n
		bufs:free(n)
	end
	mg.stop()
	print("captured packets: "..numrx)
	local h = histogram:create()
	local last
	for i, v in ipairs(times) do
		--print(i,v)
		if last then
			local diff = v - last
			h:update(diff)
		end
		last = v
	end
	--h:print()
	h:save("histogram.csv")
end


