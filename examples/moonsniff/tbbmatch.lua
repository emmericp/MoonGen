--- Matching for pcap files

local mod = {}

local memory = require "memory"
local ts     = require "timestamping"
local hist   = require "histogram"
local log    = require "log"
local ms     = require "moonsniff-io"
local dpdk   = require "dpdk"
local pcap   = require "pcap"
local hmap   = require "hmap"

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
                    -- maximum: 64 (largest supported key size for hashmap)

local TIME_THRESH = -50 -- negative timevalues smaller than this value are not allowed

local mempool0 = nil
local mempool1 = nil
local next_mempool = 0 -- used to switch between mempool 0 and mempool 1

local TABLE_TARGET_SIZE = 10000 -- approximate size for the used table
local TABLE_THRESH_SIZE = 1000 -- if table size exceeds target size + thresh size the table will be searched for
                               -- leftover entries which can be deleted
-- this value is dynamically increased during runtime
local DELETION_THRESH = 1e9 -- delete entries only if their timestamp is this value of nanoseconds older
                            -- than the latest entry which was successfully matched


--- Main matching function
--- Matches timestamps and identifications from pcap files
--- Call this function from the outside
--
-- @param PRE, filename of the pcap file containing the pre-DuT measurements
-- @param POST, filename fo the pcap file containing the post-DuT measurements
-- @param args, arguments. See post-processing.lua for a list of supported arguments
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
	log:info("Using TBB")
	return tbbCore(args, PRE, POST)
end

--- Determine the absolute path of this script
--- Needed because relative paths do not work, depending on the working directory
function script_path()
	local str = debug.getinfo(2, "S").source:sub(2)
	return str:match("(.*/)")
end

--- Setup by loading user defined function and initializing the scratchpad
function setUp()
	-- fetch user defined function
	local loaded_chunk = assert(loadfile(script_path() .. "pkt-matcher.lua"))
	pktmatch = loaded_chunk()

	-- initialize scratchpad
	scratchpad = C.malloc(ffi.sizeof(UINT8_T) * SCR_SIZE)
	scratchpad = ffi.cast(UINT8_P, scratchpad)

	-- setup the mempool
	mempool0 = memory.createMemPool()
	mempool1 = memory.createMemPool()
end

function tearDown()
	C.free(scratchpad)
end

function initReader(PRE, POST)
	return pcap:newReader(PRE), pcap:newReader(POST)
end


--- Abstract different readers from each other
--- Manage two different mempools
--
-- @param reader, the pcap reader
function readSingle(reader)
	if next_mempool == 0 then
		next_mempool = 1
		return reader:readSingle(mempool0)
	else
		next_mempool = 0
		return reader:readSingle(mempool1)
	end
	return reader:readSingle()
end

--- Save free, will free mbufs
--
-- @param the mbuf which should be freed
function sfree(cap)
	free(cap)
end


--- Extract timestamp from pcaps
--- This function is designed for the Intel X552, for other devices the computation of
--- the timestamp could be slightly different
--
-- @param cap, mbuf to extract the timestamp from
function getTs(cap)
	-- get X552 timestamps
	local timestamp = ffi.cast("uint32_t*", ffi.cast("uint8_t*", cap:getData()) + cap:getSize() - 8)
	local low = timestamp[0]
	local high = timestamp[1]
	return high * 10 ^ 9 + low
end


--- Prepare HashMap for operation
--- Initializes buffers
function initHashMap()
	-- we need the values everywhere, therefore, global
	tbbmap = hmap.createHashmap(SCR_SIZE, 8)
	tbbmap:clear()
	acc = tbbmap.newAccessor()
	local keyBuf = createBytes(SCR_SIZE)

	-- 8 byte timestamps
	local tsBuf = createBytes(8)
	tsBuf = ffi.cast(ffi.typeof("uint64_t *"), tsBuf)
	return keyBuf, tsBuf
end

--- Create a non garbage collected zero initialized byte array
--
-- @param length, length of the array in bytes
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
-- @param pre, true if pre-DuT packet, false otherwise
function extractData(cap, keyBuf, tsBuf, pre)
	-- zero fill scratchpad again
	ffi.fill(scratchpad, SCR_SIZE)

	-- as the scratchpad has been zerofilled, filled can safely be ignored
	local filled = pktmatch(cap, scratchpad, SCR_SIZE, pre)

	ffi.copy(keyBuf, scratchpad, SCR_SIZE)

	tsBuf[0] = getTs(cap)
end


--- Adds a given value to the HashMap
--- Should be called for pre-DuT packets
--
-- @param cap, the corresponding mbuf for the packet
-- @param keyBuf, reusable buffer for keys. Need not be zero initialized
-- @param tsBuf, reusable buffer for timestamps. Need not be zero initalized
function addKeyVal(cap, keyBuf, tsBuf)
	extractData(cap, keyBuf, tsBuf, true)

	-- add the data to the hashmap
	tbbmap:access(acc, keyBuf)
	ffi.copy(acc:get(), tsBuf, 8)

	acc:release()
end


--- Try to find a match in the table for a given key
--- The key is extracted from the mbuf representing a post-DuT device
--
-- @param cap, the post-DuT mbuf
-- @param misses, counter for all misses
-- @param keyBuf, reusable buffer for keys. Need not be zero initialized
-- @param tsBuf, reusable buffer for timestamps. Need not be zero initalized
-- @param lastHit, timestamp of the last successful matching operation
-- @param tableSize, the current number of entries in the table
function getKeyVal(cap, misses, keyBuf, tsBuf, lastHit, tableSize)
	extractData(cap, keyBuf, tsBuf, false)

	local found = tbbmap:find(acc, keyBuf)
	if found then
		local pre_ts = acc:get()
		local post_ts = tsBuf

		pre_ts = ffi.cast(UINT64_P, pre_ts)

		local diff = ffi.cast(INT64_T, post_ts[0] - pre_ts[0])

		if diff < TIME_THRESH then
			log:warn("Got latency smaller than defined thresh value")
			log:warn("Pre: " .. tostring(pre_ts[0]) .. "; post: " .. tostring(post_ts[0]))
			log:warn("Difference: " .. tostring(diff) .. ", thresh: " .. tostring(TIME_THRESH))
		else
			C.hs_update(diff)
		end

		-- delete associated data
		tbbmap:erase(acc)

		acc:release()
		tableSize = tableSize - 1
	else
		misses = misses + 1
	end

	return misses, lastHit, tableSize
end


--- Core loop of the program
--
-- @param args, arguments. See post-processing.lua for details on arguments
-- @param PRE, filename of the pcap file for pre-DuT measurements
-- @param POST, filename of the pcap file for post-DuT measurements
function tbbCore(args, PRE, POST)
	-- initialize scratchpad and mbufs
	setUp()
	C.hs_initialize(args.nrbuckets)
	local keyBuf, tsBuf = initHashMap()

	local lastHit = 0
	local tableSize = 0
	local packets = 0

	log:info("finished init")

	local prereader, postreader = initReader(PRE, POST)
	local precap = readSingle(prereader)
	log:info("initialized reader")

	-- prefilling
	local ctr = TABLE_TARGET_SIZE
	while precap and ctr > 0 do
		addKeyVal(precap, keyBuf, tsBuf)
		tableSize = tableSize + 1
		-- log:info("added key")
		sfree(precap)
		-- log:info("freeing")
		precap = readSingle(prereader)
		ctr = ctr - 1
		packets = packets + 1
	end


	local postcap = readSingle(postreader)
	local misses = 0
	local trash = 0
	-- map is now hot
	while precap and postcap do
		addKeyVal(precap, keyBuf, tsBuf)
		tableSize = tableSize + 1
		sfree(precap)
		precap = readSingle(prereader)

		-- now try match
		misses, lastHit, tableSize = getKeyVal(postcap, misses, keyBuf, tsBuf, lastHit, tableSize)
		sfree(postcap)
		postcap = readSingle(postreader)

		-- remove old values if table is too big
		tableSize = checkClean(lastHit, tableSize)

		packets = packets + 2
	end

	-- process leftovers
	while postcap do
		misses, lastHit, tableSize = getKeyVal(postcap, misses, keyBuf, tsBuf, lastHit, tableSize)
		sfree(postcap)
		postcap = readSingle(postreader)

		packets = packets + 1
	end


	prereader:close()
	postreader:close()

	-- free scratchpad
	tearDown()

	C.hs_finalize()

	log:info("Mean: " .. C.hs_getMean() .. " [ns], Variance: " .. C.hs_getVariance() .. " [ns]\n")

	log:info("Misses: " .. misses)
	C.hs_write(args.output .. ".csv")
	C.hs_destroy()

	return packets
end


--- Check current table size and try to delete old entries if size exceeded threshold
--
-- @param lastHist, the timestamp of the last successful matching operation
-- @param tableSize, the current number of entries in the table
function checkClean(lastHit, tableSize)
	if tableSize > TABLE_TARGET_SIZE + TABLE_THRESH_SIZE then
		log:info("Cleaning: ")
		local cleaned = tbbmap:clean(math.max(lastHit - DELETION_THRESH, 0))
		tableSize = tableSize - cleaned
		log:info("Finished cleaning")
		if cleaned == 0 then
			TABLE_THRESH_SIZE = TABLE_THRESH_SIZE * 1.4
		end
	end
	return tableSize
end


--- Write up to range entries from the pcap file as human readable csv file
--
-- @param infile, name of the pcap file
-- @param outfile, name of the csv file to write to
-- @param range, writes up to range entries (provided there are enough entries)
function writePCAPasText(infile, outfile, range)
	setUp()
	local reader = pcap:newReader(infile)
	local cap = readSingle(reader)

	local keyBuf = createBytes(SCR_SIZE)

	-- 8 byte timestamps
	local tsBuf = createBytes(8)
	tsBuf = ffi.cast(ffi.typeof("uint64_t *"), tsBuf)


	local textf = io.open(outfile, "w")

	for i = 0, range do
		local pkt = cap:getUdpPacket()
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
