--- Matching for mscap files

local mod = {}

local hist 	= require "histogram"
local log 	= require "log"
local ms 	= require "moonsniff-io"
local bit 	= require "bit"
local mem 	= require "memory"

local ffi 	= require "ffi"
local C = ffi.C
local band = bit.band

-- default values
local INDEX_BITMASK = 0x0FFFFFFF
local TIME_THRESH = -50 -- negative timevalues smaller than this value are not allowed

-- pointers and ctypes
local INT64_T = ffi.typeof("int64_t")
local UINT64_T = ffi.typeof("uint64_t")
local UINT64_P = ffi.typeof("uint64_t *")

ffi.cdef [[
	struct entry {
		uint64_t timestamp;	// the full timestamp
		uint32_t identifier;
	} __attribute__((__packed__));
]]

local ENTRY_T = ffi.typeof("struct entry")
local ENTRY_P = ffi.typeof("struct entry *")

--- Main matching function
--- Tries to match timestamps and identifications from two mscap files
--- Call this function from the outside
--
-- @param PRE, filename of the mscap file containing pre-DuT measurements
-- @param POST, filename of the mscap file containing post-DuT measurements
-- @param args, arguments. See post-processing.lua for a list of supported arguments
function mod.match(PRE, POST, args)
	if args.debug then
		log:info("Debug mode MSCAP")
		writeMSCAPasText(PRE, "pre-ts.csv", 1000)
		writeMSCAPasText(POST, "post-ts.csv", 1000)
		return
	end

	log:info("Using array matching")

	-- increase the size of map by one to make BITMASK a valid identifier
	local map = C.malloc(ffi.sizeof(ENTRY_T) * (INDEX_BITMASK + 1))
	map = ffi.cast(ENTRY_P, map)

	-- make sure the complete map is zero initialized
	zeroInit(map)

	C.hs_initialize(args.nrbuckets)

	prereader = ms:newReader(PRE)
	postreader = ms:newReader(POST)

	local precap = readSingle(prereader)
	local postcap = readSingle(postreader)
	log:info("Pre identifier: " .. tostring(getId(precap)) .. ", Post identifier: " .. tostring(getId(postcap)))

	-- debug and information values
	local overwrites = 0
	local misses = 0
	local pre_pkts = 0	-- number of packets received on pre port
	local post_pkts = 0	-- number of packets received on post port

	log:info("Prefilling Map")

	if precap == nil or postcap == nil then
		log:err("Detected either no pre or post timestamps. Aborting ..")
	end

	pre_pkts, overwrites = initialFill(precap, prereader, map)

	-- map is successfully prefilled
	log:info("Map is now hot")

	-- begin actual matching
	while precap and postcap do
		pre_pkts = pre_pkts + 1
		post_pkts = post_pkts + 1

		local ident = band(getId(precap), INDEX_BITMASK)

		if map[ident].timestamp ~= 0 then
			overwrites = overwrites + 1
		end

		map[ident].timestamp = getTs(precap)
		map[ident].identifier = getId(precap)

		precap = readSingle(prereader)

		postcap, misses = computeLatency(postcap, postreader, map, misses)
	end

	-- all pre-DuT values are already included in the map
	-- process leftover post-DuT values
	while postcap do
		post_pkts = post_pkts + 1

		postcap, misses = computeLatency(postcap, postreader, map, misses)
	end

	log:info("Finished timestamp matching")

	-- clean up
	prereader:close()
	postreader:close()
	C.free(map)

	C.hs_finalize()

	-- print final statistics
	printStats(pre_pkts, post_pkts, overwrites, misses)

	log:info("Finished processing. Writing histogram ...")
	C.hs_write(args.output .. ".csv")
	C.hs_destroy()

	return pre_pkts + post_pkts
end

--- Zero initialize the array on which the mapping will be performed
--
-- @param map, pointer to the matching-array
function zeroInit(map)
	for i = 0, INDEX_BITMASK do
		map[i].timestamp = 0
		map[i].identifier = 0
	end
end

--- Fill the array on which is matched with pre-DuT values
--
-- @param precap, the first pre-DuT mscap file
-- @param prereader, the reader for all subsequent mscaps
-- @param map, pointer to the array on which the matching is performed
function initialFill(precap, prereader, map)
	local pre_ident = band(getId(precap), INDEX_BITMASK)
	local initial_id = pre_ident

	local overwrites = 0

	local pre_pkts = 0

	log:info("end : " .. INDEX_BITMASK - 100)

	while precap and pre_ident >= initial_id and pre_ident < INDEX_BITMASK - 100 do
		pre_pkts = pre_pkts + 1

		if map[pre_ident].timestamp ~= 0 then overwrites = overwrites + 1 end
		map[pre_ident].timestamp = getTs(precap)
		map[pre_ident].identifier = getId(precap)

		precap = readSingle(prereader)
		if precap then
			pre_ident = band(getId(precap), INDEX_BITMASK)
		end
	end
	return pre_pkts, overwrites
end

--- Function to process a single entry of the post .mscap file
--- Computes the correct index in the array and checks its contents
--- If computed latencies exceed the negative threshold (e.g. -2 milliseconds) a warning is printed
--
-- @param postcap, the current mscap entry
-- @param postreader, the reader associated with the post mscap file
-- @param map, the array in which the pre timestamps are stored
-- @param misses, the number of misses which have occurred until now
-- @return the next mscap entry, or nil if mscap file is depleted
-- @return the new number of misses (either the same or misses + 1)
function computeLatency(postcap, postreader, map, misses)
	local ident = band(getId(postcap), INDEX_BITMASK)
	local ts = map[ident].timestamp
	local pre_identifier = map[ident].identifier
	local post_identifier = getId(postcap)

	if pre_identifier == post_identifier then
		local diff = ffi.cast(INT64_T, getTs(postcap) - ts)
		-- handle weird overflow bug that was introduced when we moved to the C++ capturer
		-- no idea what exactly causes this, but this work-around fixes it for all latencies less than 2 seconds
		if ts ~= 0 and diff < -2^31 and diff > -2^32 then
			diff = diff + 2^32
		end
		if ts ~= 0 and diff < TIME_THRESH then
			log:warn("Got latency smaller than defined thresh value")
			log:warn("Identification " .. ident)
			log:warn("Pre: " .. tostring(ts) .. "; post: " .. tostring(getTs(postcap)))
			log:warn("Difference: " .. tostring(diff) .. ", thresh: " .. tostring(TIME_THRESH))
		else
			if ts ~= 0 then
				C.hs_update(diff)
			else
				misses = misses + 1
			end
		end
	else
		misses = misses + 1
	end

	map[ident].timestamp = 0
	map[ident].identifier = 0

	return readSingle(postreader), misses
end


--- Prints the statistics at the end of the program
function printStats(pre_pkts, post_pkts, overwrites, misses)
	print()
	log:info("# pkts pre: " .. pre_pkts .. ", # pkts post " .. post_pkts)
	log:info("Packet loss: " .. (1 - (post_pkts / pre_pkts)) * 100 .. " %%")
	log:info("")
	log:info("# of identifications possible: " .. INDEX_BITMASK)
	log:info("Overwrites: " .. overwrites .. " from " .. pre_pkts)
	log:info("\tPercentage: " .. (overwrites / pre_pkts) * 100 .. " %%")
	log:info("")
	log:info("Misses: " .. misses .. " from " .. post_pkts)
	log:info("\tPercentage: " .. (misses / post_pkts) * 100 .. " %%")
	log:info("")
	log:info("Mean: " .. C.hs_getMean() .. " [ns], Variance: " .. C.hs_getVariance() .. " [ns]\n")
end



--- Used for debug mode only
--- Prints up to range entries from specified .mscap file as csv
--- Columns: full identification, effective identification, timestamp
--
-- @param infile, the mscap file to read from
-- @param outfile, the name of the file to write to
-- @param range, print up to range entries if there are enough entries
function writeMSCAPasText(infile, outfile, range)
	local reader = ms:newReader(infile)
	local mscap = reader:readSingle()

	local textf = io.open(outfile, "w")

	for i = 0, range do
		local ident = band(mscap.identification, INDEX_BITMASK)

		textf:write(tostring(mscap.identification), ", ", tostring(ident), ", ", tostring(mscap.timestamp), "\n")
		mscap = reader:readSingle()

		if mscap == nil then break end
	end

	reader:close()
	io.close(textf)
end

--- Read the first pre-DuT and post-DuT values
function initReader(PRE, POST)
	return ms:newReader(PRE), ms:newReader(POST)
end


--- Abstract different readers from each other
function readSingle(reader)
	return reader:readSingle()
end


--- Compute an identification of pcap files
--- Has no effect on mscap files
function getId(cap)
	return cap.identification
end

--- Extract timestamp from pcap and mscaps
function getTs(cap)
	return cap.timestamp
end

-- Get the payload identification from mscap file
-- Undefined behavior for packets without identification in the payload
function getPayloadId(cap)
	return cap.identification
end

return mod
