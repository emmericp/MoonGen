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
local ms	= require "moonsniff-io"

local ffi    = require "ffi"
local C = ffi.C

ffi.cdef[[
        struct ms_stats {
                uint64_t average_latency;
                uint32_t hits;
                uint32_t misses;
		uint32_t cold_misses;
                uint32_t inval_ts;
		uint32_t overwrites;
		uint32_t cold_overwrites;
        };

        enum ms_mode { ms_text, ms_binary };

        void ms_add_entry(uint32_t identification, uint64_t timestamp);
        void ms_test_for(uint32_t identification, uint64_t timestamp);
        void ms_init(const char* fileName, enum ms_mode mode);
        void ms_finish();
        struct ms_stats ms_post_process(const char* fileName, enum ms_mode mode);
]]

local RUN_TIME = 10		-- in seconds
local OUTPUT_PATH = "latencies.csv"
local OUTPUT_MODE = C.ms_text
local DEBUG = true

function configure(parser)
	parser:description("Demonstrate and test hardware latency induced by a device under test.\nThe ideal test setup is to use 2 taps, one should be connected to the ingress cable, the other one to the egress one.\n\n For more detailed information on possible setups and usage of this script have a look at moonsniff.md.")
	parser:argument("dev", "devices to use."):args(2):convert(tonumber)
	parser:option("-o --output", "Path to output file.")
	parser:flag("-b --binary", "Write file in binary mode (instead of human readable). For long test series this will reduce the size of the output file.")
	parser:flag("-f --fast", "Set fast flag to omit all live processing for highest performance.")
	parser:flag("-c --capture", "If set, all incoming packets are captured as a whole.")
	return parser:parse()
end

function master(args)
	if args.output then OUTPUT_PATH = args.output end
	if args.binary then OUTPUT_MODE = C.ms_binary end

	if DEBUG then

		local writer_pre = ms:newWriter(OUTPUT_PATH)
		
		writer_pre:write(10, 1000002)
		writer_pre:write(10, 2000004)
		writer_pre:write(10, 4000008)

		writer_pre:close()

		local reader = ms:newReader(OUTPUT_PATH)
		
		mscap = reader:readSingle()
		print(mscap.identification)
		print(mscap.timestamp)

		mscap = reader:readSingle()
		print(mscap.identification)
		print(mscap.timestamp)

		mscap = reader:readSingle()
		print(mscap.identification)
		print(mscap.timestamp)

		reader:close()


--		C.ms_init(OUTPUT_PATH, OUTPUT_MODE)
--
--		C.ms_add_entry(10, 10000000)
--		C.ms_add_entry(11, 20000000)
--		C.ms_test_for(10, 20000000)
--		C.ms_test_for(11, 30000000)
--
--
--        	C.ms_finish()

	else

		args.dev[1] = device.config{port = args.dev[1], txQueues = 2, rxQueues = 2}
		args.dev[2] = device.config{port = args.dev[2], txQueues = 2, rxQueues = 2}
		device.waitForLinks()
		local dev0tx = args.dev[1]:getTxQueue(0)
		local dev0rx = args.dev[1]:getRxQueue(0)
		local dev1tx = args.dev[2]:getTxQueue(0)
		local dev1rx = args.dev[2]:getRxQueue(0)

		C.ms_init(OUTPUT_PATH, OUTPUT_MODE)

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
				C.ms_add_entry(pkt.payload.uint32[0], timestamp)
			else
				C.ms_test_for(pkt.payload.uint32[0], timestamp)
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

	stats = C.ms_post_process(OUTPUT_PATH, OUTPUT_MODE)
	hits = stats.hits
	misses = stats.misses
	cold = stats.cold_misses
	invalidTS = stats.inval_ts
	overwrites = stats.overwrites
	print("Received: " .. hits + misses)
	print("\tHits: " .. hits)
	print("\tHits with invalid timestamps: " .. invalidTS)
	print("\tMisses: " .. misses)
	print("\tCold Misses: " .. cold)
	print("\tOverwrites: " .. overwrites)
	print("\tCold Overwrites: " .. stats.cold_overwrites)
	print("\tLoss by misses: " .. (misses/(misses + hits)) * 100 .. "%")
	print("\tTotal loss: " .. ((misses + invalidTS)/(misses + hits)) * 100 .. "%")
	print("Average Latency: " .. tostring(tonumber(stats.average_latency)/10^6) .. " ms")

end
