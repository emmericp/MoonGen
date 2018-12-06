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
local pcap	= require "pcap"
local ms	= require "moonsniff-io"

local ffi    = require "ffi"
local C = ffi.C

local MS_THRESH = -50  -- Live mode only! All latencies below this value [ns] will print a warning
                       -- Those values will not be included in the latency estimation

local MS_TYPE = 0b01010101

function configure(parser)
	parser:description("Demonstrate and test hardware latency induced by a device under test.\nThe ideal test setup is to use 2 taps, one should be connected to the ingress cable, the other one to the egress one.\n\n For more detailed information on possible setups and usage of this script have a look at moonsniff.md.")
	parser:argument("dev", "devices to use."):args(2):convert(tonumber)
	parser:option("-o --output", "Path to output file."):args(1):default("latencies")
	parser:option("-t --time", "Sets the length of the measurement period in seconds."):args(1):convert(tonumber):default(10)
	parser:option("--seq-offset", "Offset of the sequence number in bytes."):args(1):convert(tonumber)
	parser:flag("-l --live", "Do some live processing during packet capture. Lower performance than standard mode.")
	parser:flag("-f --fast", "Set fast flag to reduce the amount of live processing for higher performance. Only has effect if live flag is also set")
	parser:flag("-c --capture", "If set, all incoming packets are captured as a whole.")
	parser:flag("-d --debug", "Insted of reading real input, some fake input is generated and written to the output files.")
	return parser:parse()
end

function master(args)
	if args.debug then
		-- used mainly to test functionality of io
		iodebug(args)
	else
		args.dev[1] = device.config{port = args.dev[1], txQueues = 1, rxQueues = 1, rxDescs = 4096, dropEnable = false}
		args.dev[2] = device.config{port = args.dev[2], txQueues = 1, rxQueues = 1, rxDescs = 4096, dropEnable = false}
		device.waitForLinks()
		local dev0tx = args.dev[1]:getTxQueue(0)
		local dev0rx = args.dev[1]:getRxQueue(0)
		local dev1tx = args.dev[2]:getTxQueue(0)
		local dev1rx = args.dev[2]:getRxQueue(0)

		if args.live then
			stats.startStatsTask{rxDevices = {args.dev[1], args.dev[2]}}
		else
			-- if we are not live we want to print the stats to a seperate file so they are easily
			-- available for post-processing
			stats.startStatsTask{rxDevices = {args.dev[1], args.dev[2]}, file = args.output .. "-stats.csv", format = "csv"}
		end
		args.dev[1]:enableRxTimestampsAllPackets(dev0rx)
		args.dev[2]:enableRxTimestampsAllPackets(dev1rx)

		local bar = barrier:new(2)

		ts.syncClocks(args.dev[1], args.dev[2])
		args.dev[1]:clearTimestamps()
		args.dev[2]:clearTimestamps()


		-- start the tasks to sample incoming packets
		-- correct mesurement requires a packet to arrive at Pre before Post
		local receiver0 = lm.startTask("timestamp", dev0rx, args.dev[2], bar, true, args)
		local receiver1 = lm.startTask("timestamp", dev1rx, args.dev[1], bar, false, args)


		receiver0:wait()
		receiver1:wait()
		lm.stop()

		log:info("Finished all capturing/writing operations")

		if args.live then printStats(args) end
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

--	bar:wait()

	if args.live then
		C.ms_set_thresh(MS_THRESH)
		local hist = not args.fast and hist:new()
		core_online(queue, bufs, pre, hist, args)

		if not args.fast then
			log:info("Inter-arrival time distribution, this will report 0 on unsupported NICs")
			hist:print()
			if hist.numSamples == 0 then
				log:error("Received no timestamped packets.")
			end
		end
		print()

	elseif args.capture then
		local writer
		if pre then
			-- set the relative starting timestamp to 0
			writer = pcap:newWriter(args.output .. "-pre.pcap", 0)
		else
			writer = pcap:newWriter(args.output .. "-post.pcap", 0)
		end

		bar:wait()
		core_capture(queue, bufs, writer, args)
		writer:close()

	else
		local filename
		if pre then
			filename = args.output .. "-pre.mscap"
		else
			filename = args.output .. "-post.mscap"
		end

		if not args.seq_offset then
			log:error("Specify offset of sequence number with --seq-offset.")
		else
			bar:wait()
			core_offline(queue, bufs, filename, args)
		end
	end
end

function core_online(queue, bufs, pre, hist, args)
	local runtime = timer:new(args.time + 0.5)
	local lastTimestamp

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
		end
		bufs:free(rx)
	end

end

function core_offline(queue, bufs, filename, args)
	C.ms_log_pkts(queue.id, queue.qid, bufs.array, bufs.size, args.seq_offset, filename)
end

function core_capture(queue, bufs, writer, args)
	local runtime = timer:new(args.time + 0.5)

	while lm.running() and runtime:running() do
		local rx = queue:tryRecv(bufs, 1000)
		for i = 1, rx do
			local timestamp = bufs[i]:getTimestamp(queue.dev)
			-- timestamps here are given in ns
			-- the pcap module assumes floats based on seconds
			if timestamp then
				-- convert to seconds
				timestamp = timestamp / 1e9
				writer:writeBuf(timestamp, bufs[i])
			end
		end
		bufs:free(rx)
	end
end

function printStats(args)
	lm.sleepMillis(500)
	print()

	stats = C.ms_fetch_stats()
	hits = stats.hits
	misses = stats.misses
	invalidTS = stats.inval_ts
	print("Received: " .. hits + misses)
	print("\tHits: " .. hits)
	print("\tHits with invalid timestamps: " .. invalidTS)
	print("\tMisses: " .. misses)
	print("\tLoss by misses: " .. (misses/(misses + hits)) * 100 .. "%")
	print("\tTotal loss: " .. ((misses + invalidTS)/(misses + hits)) * 100 .. "%")
	print("Average latency: " .. tostring(tonumber(stats.average_latency)/10^3) .. " us")
	print("Variance of latency: " .. tostring(tonumber(stats.variance_latency)/10^3) .. " us")
end

function iodebug(args)
	local writer_pre = ms:newWriter(args.output .. "-pre.mscap")
	local writer_post = ms:newWriter(args.output .. "-post.mscap")

	writer_pre:write(10, 1000002)
	writer_post:write(10, 0000002)
	writer_pre:write(11, 2000004)
	writer_post:write(11, 3000004)
	writer_pre:write(12, 4000008)
	writer_post:write(12, 5000008)

	writer_pre:close()
	writer_post:close()

	local reader = ms:newReader(args.output .. "-pre.mscap")

	local mscap = reader:readSingle()

	while mscap do
		print(mscap.identification)
		print(mscap.timestamp)

		mscap = reader:readSingle()
	end
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

end
