--- Demonstrates and tests hardware timestamping capabilities

local lm     = require "libmoon"
local device = require "device"
local memory = require "memory"
local ts     = require "timestamping"
local hist   = require "histogram"
local timer  = require "timer"
local log    = require "log"
local stats  = require "stats"

local ffi    = require "ffi"
local C = ffi.C

ffi.cdef[[
	uint8_t ms_getCtr();
	void ms_incrementCtr();

	void ms_init_buffer(uint8_t window_size);
	void ms_add_entry(uint16_t identification);
	void ms_test_for(uint16_t identification);
	uint32_t ms_get_hits();
        uint32_t ms_get_misses();
	uint32_t ms_get_wrap_misses();
	uint32_t ms_get_forward_hits();
]]

local RUN_TIME = 5		-- in seconds
local SEND_RATE = 1000		-- in mbit/s
local PKT_LEN = 100		-- in byte

function configure(parser)
	parser:description("Demonstrate and test hardware timestamping capabilities.\nThe ideal test setup for this is a cable directly connecting the two test ports.")
	parser:argument("dev", "Devices to use."):args(2):convert(tonumber)
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

	-- initialize the ring buffer
	C.ms_init_buffer(2);

	stats.startStatsTask{txDevices = {args.dev[1]}, rxDevices = {args.dev[2]}}

	-- start the tasks to sample incoming packets
	-- correct mesurement requires a packet to arrive at Pre before Post
	local receiver0 = lm.startTask("timestampPreDuT", dev0rx)
	local receiver1 = lm.startTask("timestampPostDuT", dev1rx)

	local sender1 = lm.startTask("timestampAllPacketsSender", dev1tx)
	lm.sleepMillis(1)
	local sender0 = lm.startTask("timestampAllPacketsSender", dev0tx)



	receiver0:wait()
	receiver1:wait()

	sender0:wait()
	sender1:wait()
end

function timestampPreDuT(queue)
	queue.dev:enableRxTimestampsAllPackets(queue)
	local bufs = memory.bufArray()
	local drainQueue = timer:new(0.5)
	while lm.running and drainQueue:running() do
		local rx = queue:tryRecv(bufs, 1000)
		bufs:free(rx)
	end
	local runtime = timer:new(RUN_TIME + 0.5)
	local hist = hist:new()
	local lastTimestamp
	local count = 0
	while lm.running() and runtime:running() do
		local rx = queue:tryRecv(bufs, 1000)
		for i = 1, rx do
			local pkt = bufs[i]:getUdpPacket()
			C.ms_add_entry(pkt.payload.uint16[0])
--			print(pkt.payload.uint16[0])
			count = count + 1
			local timestamp = bufs[i]:getTimestamp(queue.dev)
			if timestamp then
				-- timestamp sometimes jumps by ~3 seconds on ixgbe (in less than a few milliseconds wall-clock time)
				if lastTimestamp and timestamp - lastTimestamp < 10^9 then
					hist:update(timestamp - lastTimestamp)
				end
				lastTimestamp = timestamp
			end
		end
		bufs:free(rx)
		C.ms_incrementCtr()
--		print("pre " .. C.ms_getCtr())
	end
	log:info("Inter-arrival time distribution, this will report 0 on unsupported NICs")
	hist:print()
	if hist.numSamples == 0 then
		log:error("Received no timestamped packets.")
	end
	print()
end

function timestampPostDuT(queue)
	queue.dev:enableRxTimestampsAllPackets(queue)
	local bufs = memory.bufArray()
	local drainQueue = timer:new(0.5)
	while lm.running and drainQueue:running() do
		local rx = queue:tryRecv(bufs, 1000)
		bufs:free(rx)
	end
	local runtime = timer:new(RUN_TIME + 0.5)
	local hist = hist:new()
	local lastTimestamp
	local count = 0
	while lm.running() and runtime:running() do
		local rx = queue:tryRecv(bufs, 1000)
		for i = 1, rx do
			local pkt = bufs[i]:getUdpPacket()
			C.ms_test_for(pkt.payload.uint16[0])
--			print(pkt.payload.uint16[0])
			count = count + 1
			local timestamp = bufs[i]:getTimestamp(queue.dev)
			if timestamp then
				-- timestamp sometimes jumps by ~3 seconds on ixgbe (in less than a few milliseconds wall-clock time)
				if lastTimestamp and timestamp - lastTimestamp < 10^9 then
					hist:update(timestamp - lastTimestamp)
				end
				lastTimestamp = timestamp
			end
		end
		bufs:free(rx)
--		print("post " .. C.ms_getCtr())
	end
	log:info("Inter-arrival time distribution, this will report 0 on unsupported NICs")
	hist:print()
	if hist.numSamples == 0 then
		log:error("Received no timestamped packets.")
	end
	print()

	print("Hits: " .. C.ms_get_hits())
	print("Hits Forward: " .. C.ms_get_forward_hits())
	print("Misses: " .. C.ms_get_misses())
	print("Misses caused by wrap-around: " .. C.ms_get_wrap_misses())
end

function timestampAllPacketsSender(queue)
        log:info("Trying to enable rx timestamping of all packets, this isn't supported by most nics")
	local pkt_id = 0
        local runtime = timer:new(RUN_TIME)
        local hist = hist:new()
        local mempool = memory.createMemPool(function(buf)
                buf:getUdpPacket():fill{
			pktLength = PKT_LEN;
		}
        end)
        local bufs = mempool:bufArray()
        if lm.running() then
                lm.sleepMillis(500)
        end
        log:info("Trying to generate ~" .. SEND_RATE .. " mbit/s")
        queue:setRate(SEND_RATE)
        local runtime = timer:new(RUN_TIME)
        while lm.running() and runtime:running() do
                bufs:alloc(PKT_LEN)

		for i, buf in ipairs(bufs) do
			local pkt = buf:getUdpPacket()
			pkt.payload.uint16[0] = pkt_id
			pkt_id = pkt_id + 1
		end

                queue:send(bufs)
        end
end

function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
