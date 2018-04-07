--- Demonstrates the basic usage of moonsniff in order to determine device induced latencies

local lm     	= require "libmoon"
local device 	= require "device"
local memory 	= require "memory"
local ts     	= require "timestamping"
local hist   	= require "histogram"
local timer  	= require "timer"
local log    	= require "log"
local stats  	= require "stats"
local barrier 	= require "barrier"

local ffi    = require "ffi"
local C = ffi.C

ffi.cdef[[
	struct ms_stats {
                uint64_t average_latency;
                uint32_t hits;
                uint32_t misses;
                uint32_t inval_ts;
        };

	void ms_add_entry(uint32_t identification, uint64_t timestamp);
	void ms_test_for(uint32_t identification, uint64_t timestamp);
	void ms_init(const char* fileName);
	void ms_finish();
	struct ms_stats ms_post_process(const char* fileName);
]]

local RUN_TIME = 20		-- in seconds
local OUTPUT_PATH = "latencies.csv"

function configure(parser)
	parser:description("Demonstrate and test hardware latency induced by a device under test.\nThe ideal test setup is to use 2 taps, one should be connected to the ingress cable, the other one to the egress one.\n\n For more detailed information on possible setups and usage of this script have a look at moonsniff.md.")
	parser:argument("dev", "devices to use."):args(2):convert(tonumber)
	parser:flag("-f --fast", "set fast flag to omit all live processing for highest performance")
	parser:flag("-c --capture", "if set, all incoming packets are captured as a whole")
	return parser:parse()
end

function master(args)
	args.dev[1] = device.config{port = args.dev[1], txQueues = 2, rxQueues = 2}
	args.dev[2] = device.config{port = args.dev[2], txQueues = 2, rxQueues = 2}
	device.waitForLinks()
	local dev0tx = args.dev[1]:getTxQueue(0)
	local dev0rx = args.dev[1]:getRxQueue(0)
	local dev1tx = args.dev[2]:getTxQueue(0)
	local dev1rx = args.dev[2]:getRxQueue(0)

	C.ms_init(OUTPUT_PATH)

	stats.startStatsTask{rxDevices = {args.dev[1], args.dev[2]}}
	
	args.dev[1]:enableRxTimestampsAllPackets(dev0rx)
	args.dev[2]:enableRxTimestampsAllPackets(dev1rx)

	local bar = barrier:new(2)

	-- start the tasks to sample incoming packets
	-- correct mesurement requires a packet to arrive at Pre before Post
	local receiver0 = lm.startTask("timestamp", dev0rx, args.dev[2], bar, true, args)
	local receiver1 = lm.startTask("timestamp", dev1rx, args.dev[1], bar, false, args)


	receiver0:wait()
	receiver1:wait()
	lm.stop()

	C.ms_finish()

	printStats()
end

function timestamp(queue, otherdev, bar, pre, args)
--	queue.dev:enableRxTimestampsAllPackets(queue)
	local bufs = memory.bufArray()
	local drainQueue = timer:new(0.5)
	while lm.running and drainQueue:running() do
		local rx = queue:tryRecv(bufs, 1000)
		bufs:free(rx)
	end
	if not pre then
		ts.syncClocks(queue.dev, otherdev)
		queue.dev:clearTimestamps()
		otherdev:clearTimestamps()
	end

	bar:wait()
	local runtime = timer:new(RUN_TIME + 0.5)
	local hist = not args.fast and hist:new()
	local lastTimestamp
	local count = 0
	while lm.running() and runtime:running() do
		local rx = queue:tryRecv(bufs, 1000)
		for i = 1, rx do
			local timestamp = bufs[i]:getTimestamp(queue.dev)
			if not args.fast and timestamp then
				-- timestamp sometimes jumps by ~3 seconds on ixgbe (in less than a few milliseconds wall-clock time)
				if lastTimestamp and timestamp - lastTimestamp < 10^9 then
					hist:update(timestamp - lastTimestamp)
				end
				lastTimestamp = timestamp
			end
--			print("Pre: " .. timestamp)
			local pkt = bufs[i]:getUdpPacket()

			if pre then
				C.ms_add_entry(pkt.payload.uint16[0], timestamp)
			else
				C.ms_test_for(pkt.payload.uint16[0], timestamp)
			end
			count = count + 1

		end
		bufs:free(rx)
	end

	if not args.fast then
		log:info("Inter-arrival time distribution, this will report 0 on unsupported NICs")
		hist:print()
		if hist.numSamples == 0 then
			log:error("Received no timestamped packets.")
		end
	end
	print()
end

function printStats()
	lm.sleepMillis(500)
	print()

	stats = C.ms_post_process(OUTPUT_PATH)
	hits = stats.hits
	misses = stats.misses
	invalidTS = stats.inval_ts
	print("Received: " .. hits + misses)
	print("\tHits: " .. hits)
	print("\tHits with invalid timestamps: " .. invalidTS)
	print("\tMisses: " .. misses)
	print("\tLoss by misses: " .. (misses/(misses + hits)) * 100 .. "%")
	print("\tTotal loss: " .. ((misses + invalidTS)/(misses + hits)) * 100 .. "%")
	print("Average Latency: " .. tostring(tonumber(stats.average_latency)/10^6) .. " ms")

end
