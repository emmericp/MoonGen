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
local hmap 	= require "hmap"

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
local UINT8_T = ffi.typeof("uint8_t")
local UINT8_P = ffi.typeof("uint8_t*")

local free = C.rte_pktmbuf_free_export
local band = bit.band

local pktmatch = nil
local scratchpad = nil
local SCR_SIZE = 16 -- size of the scratchpad in bytes, must always be multiple of 8 for hash to work
local mempool = nil
local SIP_KEY = ffi.new("uint64_t[2]", {1, 2})

-- skip the initialization of DPDK, as it is not needed for this script
dpdk.skipInit()

function configure(parser)
        parser:description("Demonstrate and test hardware latency induced by a device under test.\nThe ideal test setup is to use 2 taps, one should be connected to the ingress cable, the other one to the egress one.\n\n For more detailed information on possible setups and usage of this script have a look at moonsniff.md.")
	parser:flag("-d --debug", "Create additional debug information")
        return parser:parse()
end

ffi.cdef[[
	void* malloc(size_t);
	void free(void*);

	uint32_t ms_hash(void*);
	uint32_t ms_get_identifier(void*);

	uint64_t SipHashC(const uint64_t* key, const char* bytes, const uint64_t size);


	struct deque_entry{
                uint8_t *key;
               	uint8_t *timestamp;
        };

	void *deque_create();
	struct deque_entry deque_peek_back(void *queue);
	void deque_remove_back(void *queue);
	void deque_push_front(void *queue, struct deque_entry entry);
]]

function master(args)
	local q = C.deque_create();

	local entry = ffi.new("struct deque_entry", {})
	entry.timestamp = ffi.new("uint8_t [5]", {10, 5})
	entry.key = ffi.new("uint8_t [5]", {})

	C.deque_push_front(q, entry);
	local otherentry = C.deque_peek_back(q);
	print(otherentry.timestamp[0])

	local map = hmap.createHashmap(16, 8)
	if map == nil then
		print("was nil")
	else
		print("not nil")
	end
	map:clear()

	local acc = map.newAccessor()
	local key = ffi.new("uint8_t [16]", {1,2,3})

	map:access(acc, key)
	local val = acc:get()
	val[0] = 11


	acc:release()

	local newacc = map.newAccessor()
	--false key
	key[0] = 2
	local found = map:find(newacc, key)
	print(found)

	local result = newacc:get()
	print(result[0])
end
