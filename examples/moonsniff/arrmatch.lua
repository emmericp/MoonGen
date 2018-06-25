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

-- default values when no cli options are specified
local INPUT_PATH = "latencies.csv"
local INPUT_MODE = C.ms_text
local BITMASK = 0x0FFFFFFF
local TIME_THRESH = -50 	-- negative timevalues smaller than this value are not allowed

local MODE_MSCAP, MODE_PCAP = 0, 1
local MODE = MODE_MSCAP

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
local SIP_KEY = ffi.new("uint64_t[2]", {1, 2})

ffi.cdef[[
	void* malloc(size_t);
	void free(void*);

	uint32_t ms_hash(void*);
	uint32_t ms_get_identifier(void*);

	uint64_t SipHashC(const uint64_t* key, const char* bytes, const uint64_t size);
]]

function mod.match(PRE, POST, args)
	if args.debug then
                log:info("Debug mode MSCAP")
                writeMSCAPasText(PRE, "pre-ts.csv", 1000)
                writeMSCAPasText(POST, "post-ts.csv", 1000)
                return
        end

	log:info("Using array matching")
	MODE = MODE_MSCAP

	local uint64_t = ffi.typeof("uint64_t")
	local uint64_p = ffi.typeof("uint64_t*")

	-- increase the size of map by one to make BITMASK a valid identifier
	local map = C.malloc(ffi.sizeof(uint64_t) * (BITMASK + 1))
	map = ffi.cast(uint64_p, map)

	-- make sure the complete map is zero initialized
	zeroInit(map)

	-- initialize pcap stuff if needed
	setUp()

	C.hs_initialize(args.nrbuckets)

	local prereader = nil
	local postreader = nil

	if MODE == MODE_MSCAP then
		prereader = ms:newReader(PRE)
		postreader = ms:newReader(POST)
	else
		prereader = pcap:newReader(PRE)
		postreader = pcap:newReader(POST)
	end

	-- TODO: check if there are problems with the shared mempool
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

	log:info("Map is now hot")

	while precap and postcap do
		pre_count = pre_count + 1
		post_count = post_count + 1

		local ident = band(getId(precap), BITMASK)

		if map[ident] ~= 0 then
			overwrites = overwrites + 1
		end

		map[ident] = getTs(precap)

		sfree(precap)
		precap = readSingle(prereader)

		post_ident = band(getId(postcap), BITMASK)

		local ts = map[post_ident]

		local diff = ffi.cast(INT64_T, getTs(postcap) - ts)

		-- check for time measurements which violate the given threshold
		if ts ~= 0 and diff < TIME_THRESH then
			log:warn("Got negative timestamp")
			log:warn("Identification " .. ident)
			log:warn("Postcount: " .. post_count)
			log:warn("Pre: " .. tostring(ts) .. "; post: " .. tostring(getTs(postcap)))
			log:warn("Difference: " .. tostring(diff))
			return

		else
			if ts ~= 0 then
				C.hs_update(diff)

				-- reset the ts field to avoid matching it again
				map[ident] = 0
			else
				misses = misses + 1
			end
			sfree(postcap)
			postcap = readSingle(postreader)
		end
	end

	while postcap do
		post_count = post_count + 1

		local ident = band(getId(postcap), BITMASK)
		local ts = map[ident]

		local diff = ffi.cast(INT64_T, getTs(postcap) - ts)

		if ts ~= 0 and diff < TIME_THRESH then
			log:warn("Got negative timestamp")
			log:warn("Identification " .. ident)
			log:warn("Postcount: " .. post_count)
			log:warn("Pre: " .. tostring(ts) .. "; post: " .. tostring(getTs(postcap)))
			log:warn("Difference: " .. tostring(diff))
			return

		elseif ts ~= 0 then

			C.hs_update(diff)

			-- reset the ts field to avoid matching it again
			map[ident] = 0
		else
			misses = misses + 1
		end
		sfree(postcap)
		postcap = readSingle(postreader)
	end

	log:info("Finished timestamp matching")

	prereader:close()
	postreader:close()
	C.free(map)

	tearDown()

	C.hs_finalize()


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
	log:info("Mean: " .. C.hs_getMean() .. ", Variance: " .. C.hs_getVariance() .. "\n")

	log:info("Finished processing. Writing histogram ...")
	C.hs_write(args.output .. ".csv")
	C.hs_destroy()
end

function zeroInit(map)
	for i = 0, BITMASK do
		map[i] = 0
	end
end

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

		-- save free in case of pcaps
		sfree(precap)
                precap = readSingle(prereader)
                if precap then
                        pre_ident = band(getId(precap), BITMASK)
                end
        end
	return pre_count, overwrites
end

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


--- Setup by loading user defined function and initializing the scratchpad
--- Has no effect if in MODE_MSCAP
function setUp()
	if MODE == MODE_PCAP then
		-- in case of pcap files we need DPDK functions
		dpdk.init()

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
end

function tearDown()
	C.free(scratchpad)
end

function initReader(PRE, POST)
	if MODE == MODE_MSCAP then
		return ms:newReader(PRE), ms:newReader(POST)
	else
		return pcap:newReader(PRE), pcap:newReader(POST)
	end
end


--- Abstract different readers from each other
function readSingle(reader)
	if MODE == MODE_PCAP then
		if next_mem == 0 then
			next_mem = 1
			return reader:readSingle(mempool)
		else
			next_mem = 0
			return reader:readSingle(mempool2)
		end
	else
		return reader:readSingle()
	end
end

--- Save free, will free mbufs
function sfree(cap)
	if MODE == MODE_PCAP then
		free(cap)
	end
end

--- Compute an identification of pcap files
--- Has no effect on mscap files
function getId(cap)
	if MODE == MODE_PCAP then
		-- zero fill scratchpad again
		for i = 0, SCR_SIZE do
			scratchpad[i] = 0
		end

		local filled = pktmatch(cap, scratchpad, SCR_SIZE)
	--	print(scratchpad[0] .. ", " .. scratchpad[1] .. ", " .. scratchpad[2] .. ", " .. scratchpad[3])
		-- log:info("Sip hash of the scratchpad")
		local hash64 = C.SipHashC(SIP_KEY, scratchpad, filled)
		-- log:info("hash: " .. tostring(hash64))

		return hash64
	else
		return cap.identification
	end
end

--- Extract timestamp from pcap and mscaps
function getTs(cap)
	if MODE == MODE_PCAP then
		-- get X552 timestamps
		local timestamp = ffi.cast("uint32_t*", ffi.cast("uint8_t*", cap:getData()) + cap:getSize() - 8)
		local low = timestamp[0]
		local high = timestamp[1]
		return high * 10^9 + low
	else
		return cap.timestamp
	end
end

-- Get the payload identification from pcap file
-- Undefined behavior for packets without identification in the payload
function getPayloadId(cap)
	if MODE == MODE_PCAP then
		local pkt = cap:getUdpPacket()
		return pkt.payload.uint32[0]
	else
		return cap.identification
	end
end

return mod
