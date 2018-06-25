local mod = {}

--- Demonstrates the basic usage of moonsniff in order to determine device induced latencies

local lm        = require "libmoon"
local device    = require "device"
local memory    = require "memory"
local ts        = require "timestamping"
local hist      = require "histogram"
local timer     = require "timer"
local log       = require "log"
local stats     = require "stats"
local barrier   = require "barrier"
local ms	= require "moonsniff-io"
local bit	= require "bit"
local dpdk	= require "dpdk"
local pcap	= require "pcap"
local hmap	= require "hmap"
local profile 	= require "jit.p"

local ffi    = require "ffi"
local C = ffi.C

-- pointers and ctypes
local CHAR_P = ffi.typeof("char *")
local INT64_T = ffi.typeof("int64_t")
local UINT64_P = ffi.typeof("uint64_t *")
local UINT8_T = ffi.typeof("uint8_t")
local UINT8_P = ffi.typeof("uint8_t*")

local free = C.rte_pktmbuf_free_export
local band = bit.band

local pktmatch = nil
local scratchpad = nil
local SCR_SIZE = 16 -- size of the scratchpad in bytes, must always be multiple of 8 for hash to work
local mempool = nil
local mempool2 = nil
local next_mem = 0

ffi.cdef[[
	void* malloc(size_t);
	void free(void*);

	// deque definitions
	struct deque_entry{
                uint8_t key[16];
                uint8_t timestamp[8];
        };

        void *deque_create();
        struct deque_entry deque_peek_back(void *queue);
        void deque_remove_back(void *queue);
        void deque_push_front(void *queue, struct deque_entry entry);
	bool deque_empty(void *queue);
]]


function mod.match(PRE, POST, args)
	-- in case of pcap files we need DPDK functions
	dpdk.init()

	if args.debug then
		log:info("Debug mode PCAP")
		writePCAPasText(PRE, "pre-ts.csv", 1000)
		writePCAPasText(POST, "post-ts.csv", 1000)
		return
	end

	-- use new tbb matching mode
	local file = assert(io.open(PRE, "r"))
	local size = fsize(file)
	file:close()
	file = assert(io.open(POST, "r"))
	size = size + fsize(file)
	file:close()
	log:info("File size: " .. size / 1e9 .. " [GB]")
	local nClock = os.clock()
	profile.start("-fl", "somefile.txt")
	log:info("Using TBB")
	tbbCore(args, PRE, POST)
	profile.stop()

	local elapsed = os.clock() - nClock
	log:info("Elapsed time core: " .. elapsed .. " [sec]")
	log:info("Processing speed: " .. (size / 1e6) / elapsed .. " [MB/s]")
	return
end


--- Setup by loading user defined function and initializing the scratchpad
--- Has no effect if in MODE_MSCAP
function setUp()
	-- fetch user defined function
	loaded_chunk = assert(loadfile("examples/moonsniff/pkt-matcher.lua"))
	pktmatch = loaded_chunk()

	-- initialize scratchpad
	scratchpad = C.malloc(ffi.sizeof(UINT8_T) * SCR_SIZE)
	scratchpad = ffi.cast(UINT8_P, scratchpad)

	-- setup the mempool
	mempool = memory.createMemPool()
	mempool2 = memory.createMemPool()
end

function tearDown()
	C.free(scratchpad)
end

function initReader(PRE, POST)
	return pcap:newReader(PRE), pcap:newReader(POST)
end


--- Abstract different readers from each other
function readSingle(reader)
	if next_mem == 0 then
		next_mem = 1
		return reader:readSingle(mempool)
	else
		next_mem = 0
		return reader:readSingle(mempool2)
	end
	return reader:readSingle()
end

--- Save free, will free mbufs
function sfree(cap)
	free(cap)
end


--- Extract timestamp from pcap and mscaps
function getTs(cap)
	-- get X552 timestamps
	local timestamp = ffi.cast("uint32_t*", ffi.cast("uint8_t*", cap:getData()) + cap:getSize() - 8)
	local low = timestamp[0]
	local high = timestamp[1]
	return high * 10^9 + low
end

-- Get the payload identification from pcap file
-- Undefined behavior for packets without identification in the payload
function getPayloadId(cap)
	local pkt = cap:getUdpPacket()
	return pkt.payload.uint32[0]
end

function initHashMap()
	-- we need the values everywhere, therefore, global
	tbbmap = hmap.createHashmap(16, 8)
	tbbmap:clear()
	acc = tbbmap.newAccessor()
	deque = C.deque_create();
	local keyBuf = createBytes(16)

	-- 8 byte timestamps
	local tsBuf = createBytes(8)
	tsBuf = ffi.cast(ffi.typeof("uint64_t *"), tsBuf)
	return keyBuf, tsBuf
end

-- Create a non garbage collected zero initialized byte array
function createBytes(length)
	local bytes = C.malloc(ffi.sizeof(UINT8_T) * length)
        bytes = ffi.cast(UINT8_P, bytes)

	ffi.fill(bytes, length)
	return bytes
end

--- Extract data from an pcap file
--- This is done by an external userdefined function pktmatch which selects some
--- values of the pcap file and copies them into the given buffer
--- Additionally hardware timestamps which are located at the end of the pcap file
--- will be extracted into a seperate buffer
--
-- @param cap the pcap file to extract the data from
-- @param keyBuf a buffer into which the data selcetd by the udf is copied
-- @param tsBuf a buffer into which the timestamp is copied
function extractData(cap, keyBuf, tsBuf)
	-- zero fill scratchpad again
	ffi.fill(scratchpad, SCR_SIZE)

	-- TODO: think again what purpose filled should have ...
	local filled = pktmatch(cap, scratchpad, SCR_SIZE)

--	log:info("filled")

--	log:info("created bytes")
	ffi.copy(keyBuf, scratchpad, 16)

--	log:info("Got key")
--	log:info("TS: " .. tostring(getTs(cap)))

	tsBuf[0] = getTs(cap)
--	log:info("TS after copy: " .. tostring(tmp[0]))
--	log:info("finished copying the timestamp")
end


function addKeyVal(cap, keyBuf, tsBuf, entryBuf)
--	log:info("start of addKeyVal")
	extractData(cap, keyBuf, tsBuf)

--	log:info("try adding")

	-- add the data to the hashmap
	tbbmap:access(acc, keyBuf)
	ffi.copy(acc:get(), tsBuf, 8)

	acc:release()

--	log:info("deque")

	-- add data to the deque
--	local entry = C.malloc(ffi.sizeof(ffi.typeof("struct deque_entry")))
--	local entry = ffi.new("struct deque_entry", {});
	ffi.copy(entryBuf.key, keyBuf, 16)
	ffi.copy(entryBuf.timestamp, tsBuf, 8)
	C.deque_push_front(deque, entryBuf)
end

function getKeyVal(cap, misses, keyBuf, tsBuf, lastHit)
	extractData(cap, keyBuf, tsBuf)

	local found = tbbmap:find(acc, keyBuf)
	if found then
		local pre_ts = acc:get()
		local post_ts = tsBuf

		pre_ts = ffi.cast(UINT64_P, pre_ts)

--		log:info("Pre: " .. tostring(pre_ts[0]) .. " Post: " .. tostring(post_ts[0]))
		local diff = post_ts[0] - pre_ts[0]
		C.hs_update(diff)

		lastHit = post_ts[0]

--		log:info("Diff: " .. tostring(diff))

		-- delete associated data
		tbbmap:erase(acc)

		acc:release()
	else
		misses = misses + 1
	end

	releaseOld(lastHit)
	return misses, lastHit
end

function releaseOld(lastHit)
	while not C.deque_empty(deque) do
		local entry = C.deque_peek_back(deque)
		local key = entry.key
		local ts = ffi.cast(UINT64_P, entry.timestamp)[0]
--		log:info("TS from queue: " .. tonumber(ts))

		-- check if the current timestamp is old enough
		if ts + 10e6 < lastHit then
			local found = tbbmap:find(acc, key)
			if found then
				local map_ts = ffi.cast(UINT64_P, acc:get())[0]
				if map_ts == ts then
					-- found corrsponding value -> erase it
					tbbmap:erase(acc)
				end
			end

			acc:release()

			-- remove from deque
			C.deque_remove_back(deque)
		else
			break
		end
	end
end

function tbbCore(args, PRE, POST)
	-- initialize scratchpad and mbufs
	setUp()
	C.hs_initialize(args.nrbuckets)
	local keyBuf, tsBuf = initHashMap()
	local entryBuf = ffi.new("struct deque_entry", {});

	local lastHit = 0

	log:info("finished init")

	local prereader, postreader = initReader(PRE, POST)
	local precap = readSingle(prereader)
	log:info("initialized reader")

	-- prefilling
	local ctr = 10000
	while precap and ctr > 0 do
		addKeyVal(precap, keyBuf, tsBuf, entryBuf)
--		log:info("added key")
		sfree(precap)
--		log:info("freeing")
		precap = readSingle(prereader)
	end

	log:info("done prefilling")

	local postcap = readSingle(postreader)
	local misses = 0
	-- map is now hot
	while precap and postcap do
		addKeyVal(precap, keyBuf, tsBuf, entryBuf)
		sfree(precap)
		precap = readSingle(prereader)

		-- now try match
		misses, lastHit = getKeyVal(postcap, misses, keyBuf, tsBuf, lastHit)
		sfree(postcap)
		postcap = readSingle(postreader)
	end

	-- process leftovers
	while postcap do
		misses, lastHit = getKeyVal(postcap, misses, keyBuf, tsBuf, lastHit)
		sfree(postcap)
		postcap = readSingle(postreader)
	end


	prereader:close()
	postreader:close()

	-- free scratchpad
	tearDown()

	C.hs_finalize()

	log:info("Mean: " .. C.hs_getMean() .. ", Variance: " .. C.hs_getVariance() .. "\n")

	log:info("Misses: " .. misses)
	C.hs_destroy()
end

function fsize(file)
	local current = file:seek()
	local size = file:seek("end")
	file:seek("set", current)
	return size
end

function writePCAPasText(infile, outfile, range)
        setUp()
        local reader = pcap:newReader(infile)
        cap = readSingle(reader)

	local keyBuf = createBytes(16)

        -- 8 byte timestamps
        local tsBuf = createBytes(8)
        tsBuf = ffi.cast(ffi.typeof("uint64_t *"), tsBuf)


        textf = io.open(outfile, "w")

        for i = 0, range do
                pkt = cap:getUdpPacket()
		extractData(cap, keyBuf, tsBuf)

                textf:write(tostring(pkt.payload.uint32[0]) .. ", " .. tostring(tsBuf[0]), "\n")
                sfree(cap)
                cap = readSingle(reader)

                if cap == nil then break end
        end

        reader:close()
        io.close(textf)

        tearDown()
end

return mod
