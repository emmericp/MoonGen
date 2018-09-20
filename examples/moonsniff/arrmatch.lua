--- Matching for mscap files

local mod = {}

local hist      = require "histogram"
local log       = require "log"
local ms	= require "moonsniff-io"
local bit	= require "bit"

local ffi    = require "ffi"
local C = ffi.C
local band = bit.band

-- default values when no cli options are specified
local INPUT_PATH = "latencies.csv"
local BITMASK = 0x0FFFFFFF
local TIME_THRESH = -50 	-- negative timevalues smaller than this value are not allowed


-- pointers and ctypes
local INT64_T = ffi.typeof("int64_t")
local UINT64_T = ffi.typeof("uint64_t")
local UINT64_P = ffi.typeof("uint64_t *")

ffi.cdef[[
	void* malloc(size_t);
	void free(void*);
]]

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
	local map = C.malloc(ffi.sizeof(UINT64_T) * (BITMASK + 1))
	map = ffi.cast(UINT64_P, map)

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
	local pre_count = 0
	local post_count = 0

	log:info("Prefilling Map")

	if precap == nil or postcap == nil then
		log:err("Detected either no pre or post timestamps. Aborting ..")
	end

	pre_count, overwrites = initialFill(precap, prereader, map)

	-- map is successfully prefilled
	log:info("Map is now hot")

	-- begin actual matching
	while precap and postcap do
		pre_count = pre_count + 1
		post_count = post_count + 1

		local ident = band(getId(precap), BITMASK)

		if map[ident] ~= 0 then
			overwrites = overwrites + 1
		end

		map[ident] = getTs(precap)

		precap = readSingle(prereader)

		postcap, misses = computeLatency(postcap, postreader, map, misses)
	end

	-- all pre-DuT values are already included in the map
	-- process leftover post-DuT values
	while postcap do
		post_count = post_count + 1

		postcap, misses = computeLatency(postcap, postreader, map, misses)
	end

	log:info("Finished timestamp matching")

	-- clean up
	prereader:close()
	postreader:close()
	C.free(map)

	C.hs_finalize()

	-- print final statistics
	printStats(pre_count, post_count, overwrites, misses)

	log:info("Finished processing. Writing histogram ...")
	C.hs_write(args.output .. ".csv")
	C.hs_destroy()

	return pre_count + post_count
end

--- Zero initialize the array on which the mapping will be performed
--
-- @param map, pointer to the matching-array
function zeroInit(map)
	for i = 0, BITMASK do
		map[i] = 0
	end
end

--- Fill the array on which is matched with pre-DuT values
--
-- @param precap, the first pre-DuT mscap file
-- @param prereader, the reader for all subsequent mscaps
-- @param map, pointer to the array on which the matching is performed
function initialFill(precap, prereader, map)
        pre_ident = band(getId(precap), BITMASK)
        initial_id = pre_ident

	local overwrites = 0

        local pre_count = 0

        log:info("end : " .. BITMASK - 100)

        while precap and pre_ident >= initial_id and pre_ident < BITMASK - 100 do
                pre_count = pre_count + 1

                if map[pre_ident] ~= 0 then overwrites = overwrites + 1 end
                map[pre_ident] = getTs(precap)

                precap = readSingle(prereader)
                if precap then
                        pre_ident = band(getId(precap), BITMASK)
                end
        end
	return pre_count, overwrites
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
	local ident = band(getId(postcap), BITMASK)
	local ts = map[ident]
	local diff = ffi.cast(INT64_T, getTs(postcap) - ts)

	-- check for time measurements which violate the given threshold
	if ts ~= 0 and diff < TIME_THRESH then
		log:warn("Got negative timestamp")
		log:warn("Identification " .. ident)
		log:warn("Pre: " .. tostring(ts) .. "; post: " .. tostring(getTs(postcap)))
		log:warn("Difference: " .. tostring(diff))
		map[ident] = 0
	else
		if ts ~= 0 then
			C.hs_update(diff)

			-- reset the ts field to avoid matching it again
			map[ident] = 0
		else
			misses = misses + 1
		end
	end

	return readSingle(postreader), misses
end


--- Prints the statistics at the end of the program
function printStats(pre_count, post_count, overwrites, misses)
	print()
	log:info("# pkts pre: " .. pre_count .. ", # pkts post " .. post_count)
	log:info("Packet loss: " .. (1 - (post_count/pre_count)) * 100 .. " %%")
	log:info("")
	log:info("# of identifications possible: " .. BITMASK)
	log:info("Overwrites: " .. overwrites .. " from " .. pre_count)
	log:info("\tPercentage: " .. (overwrites/pre_count) * 100 .. " %%")
	log:info("")
	log:info("Misses: " .. misses .. " from " .. post_count)
	log:info("\tPercentage: " .. (misses/post_count) * 100 .. " %%")
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
	mscap = reader:readSingle()

	textf = io.open(outfile, "w")

	for i = 0, range do
		local ident = band(mscap.identification, BITMASK)

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
