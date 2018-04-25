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


function configure(parser)
	parser:description("Demonstrate and test hardware latency induced by a device under test.\nThe ideal test setup is to use 2 taps, one should be connected to the ingress cable, the other one to the egress one.\n\n For more detailed information on possible setups and usage of this script have a look at moonsniff.md.")
	parser:argument("dev", "devices to use."):args(2):convert(tonumber)
	parser:option("-o --output", "Path to output file."):args(1):default("latencies")
	parser:option("-r --runtime", "Sets the length of the measurement period in seconds."):args(1):convert(tonumber):default(10)
	parser:flag("-b --binary", "Write file in binary mode (instead of human readable). For long test series this will reduce the size of the output file.")
	parser:flag("-l --live", "Do some live processing during packet capture. Lower performance than standard mode.")
	parser:flag("-f --fast", "Set fast flag to reduce the amount of live processing for higher performance. Only has effect if live flag is also set")
	parser:flag("-c --capture", "If set, all incoming packets are captured as a whole.")
	parser:flag("-d --debug", "Insted of reading real input, some fake input is generated and written to the output files.")
	return parser:parse()
end

function master(args)
	args.binary = C.ms_text and C.ms_text or C.ms_binary
	if args.debug then
		-- used mainly to test functionality of io
		iodebug(args)
	else
		args.dev[1] = device.config{port = args.dev[1], txQueues = 2, rxQueues = 2}
		args.dev[2] = device.config{port = args.dev[2], txQueues = 2, rxQueues = 2}
		device.waitForLinks()
		local dev0tx = args.dev[1]:getTxQueue(0)
		local dev0rx = args.dev[1]:getRxQueue(0)
		local dev1tx = args.dev[2]:getTxQueue(0)
		local dev1rx = args.dev[2]:getRxQueue(0)

		if args.live then C.ms_init(args.output .. ".csv", args.binary) end

		stats.startStatsTask{rxDevices = {args.dev[1], args.dev[2]}}
		
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

		if args.live then C.ms_finish() end

		log:info("Finished all capturing/writing operations")

		printStats(args)
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

	else
		local writer
		if pre then 
			writer = ms:newWriter(args.output .. "-pre.mscap")
		else
			writer = ms:newWriter(args.output .. "-post.mscap")
		end
		
		bar:wait()
		core_offline(queue, bufs, writer, args)
		writer:close()
	end
end

function core_online(queue, bufs, pre, hist, args)
	local runtime = timer:new(args.runtime + 0.5)
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

function core_offline(queue, bufs, writer, args)
	local runtime = timer:new(args.runtime + 0.5)

	while lm.running() and runtime:running() do
		local rx = queue:tryRecv(bufs, 1000)
		for i = 1, rx do
			local timestamp = bufs[i]:getTimestamp(queue.dev)
			if timestamp then
				local pkt = bufs[i]:getUdpPacket()
				writer:write(pkt.payload.uint32[0], timestamp)
			end
		end
		bufs:free(rx)
	end
end

function printStats(args)
	lm.sleepMillis(500)
	print()

	stats = C.ms_post_process(args.output .. ".csv", args.binary)
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
	print("Average Latency: " .. tostring(tonumber(stats.average_latency)/10^3) .. " us")

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
