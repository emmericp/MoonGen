local ffi = require "ffi"

--require "utils"
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local serpent = require "Serpent"
require "memory"
--local burst = require "burst"

ffi.cdef [[

struct rte_table_lpm_params {
	uint32_t n_rules;
	uint32_t entry_unique_size;
	uint32_t offset;
};
void * mg_table_lpm_create(void *params, int socket_id, uint32_t entry_size);
int mg_table_lpm_free(void *table);
int mg_table_entry_add_simple(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry);
int mg_table_lpm_entry_add(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry,
	int *key_found,
	void **entry_ptr);
int mg_table_lpm_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries);
int mg_table_lpm_lookup_big_burst(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* pkts_mask,
	struct mg_bitmask* lookup_hit_mask,
	void **entries);
int mg_table_lpm_entry_delete(
	void *table,
  uint32_t ip,
  uint8_t depth,
	int *key_found,
	void *entry);
void ** mg_lpm_table_allocate_entry_prts(uint16_t n_entries);
int printf(const char *fmt, ...);

]]


local mod = {}

local mg_lpm4Table = {}
mod.mg_lpm4Table = mg_lpm4Table
mg_lpm4Table.__index = mg_lpm4Table

--- Create a new LPM lookup table.
-- @param socket optional (default = socket of the calling thread), CPU socket, where memory for the table should be allocated.
-- @return the table handler
function mod.createLpm4Table(socket, table, entry_ctype)
  -- FIXME: understand getCore and select
  socket = socket or select(2, dpdk.getCore())
    -- configure parameters for the LPM table
  local params = ffi.new("struct rte_table_lpm_params")
  params.n_rules = 1000
  params.entry_unique_size = 5
  --params.offset = 128 + 27+4
  params.offset = 128+ 14 + 12+4
  return setmetatable({
    table = table or ffi.C.mg_table_lpm_create(params, socket, ffi.sizeof(entry_ctype)),
    entry_ctype = entry_ctype
  }, mg_lpm4Table)
end

--- Free the LPM Table
-- @return 0 on success, error code otherwise
function mg_lpm4Table:destruct()
  return ffi.C.mg__table_lpm_free(self.table)
end

--- Add an entry to a Table
-- @param addr IPv4 network address of the destination network.
-- @param depth number of significant bits of the destination network address
-- @param entry routing table entry
-- @return true if entry was added without error
function mg_lpm4Table:addEntry(addr, depth, entry)
  return 0 == ffi.C.mg_table_entry_add_simple(self.table, addr, depth, entry)
end

--- Perform IPv4 route lookup for a burst of packets
-- @param packets Array of mbufs (bufArray), for which the lookup will be performed
-- @param mask optional (default = all packets), bitmask, for which packets the lookup should be performed
-- @param routes Preallocated routing entry list (mg_lpmRoutes)
function mg_lpm4Table:lookupBurst(packets, mask, hitMask, entries)
  -- FIXME: I feel uneasy about this cast, should this cast not be
  --  done implicitly?
  return ffi.C.mg_table_lpm_lookup_big_burst(self.table, packets.array, mask.bitmask, hitMask.bitmask, ffi.cast("void **",entries.array))
end

function mg_lpm4Table:__serialize()
	return "require 'lpm'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('lpm').mg_lpm4Table"), true
end

--- Allocates an LPM table entry
-- @return The newly allocated entry
function mg_lpm4Table:allocateEntry()
  return ffi.new(self.entry_ctype)
end

local mg_lpm4EntryPtrs = {}

function mg_lpm4Table:allocateEntryPtrs(n)
  -- return ffi.C.mg_lpm_table_allocate_entry_prts(n)
  return setmetatable({
    array = ffi.new(self.entry_ctype .. "*[?]", n)
  }, mg_lpm4EntryPtrs)
end

function mg_lpm4EntryPtrs:__index(k)
	if type(k) == "number" then
    return self.array[k - 1]
  else
    return mg_lpm4EntryPtrs[k]
  end
end

----- Constructs a LPM table entry for IPv4
---- @return LPM table entry of ctype "struct mg_lpm4_table_entry"
--function mod.constructLpm4TableEntry(ip_next_hop, interface, mac_next_hop)
--  entry = ffi.new("struct mg_lpm4_table_entry")
--  entry.ip_next_hop = ip_next_hop
--  entry.interface = interface
--  entry.mac_next_hop = mac_next_hop
--  return entry
--end

-- function mod.allocateLpm4Routes()
--   return ffi.new("struct mg_lpm4_routes")
-- end
-- 
-- local mg_lpm4Routes = {}
-- mg_lpm4Routes.__index = mg_lpm4Routes
-- 
-- ----- Returns a routing table entry
-- ---- @return corresponding routing entry, if valid. false otherwise
-- function mg_lpm4Routes:get(n)
--   local hit = band(self.hit_mask, lshift(1,n-1)) ~= 0
--   return hit and self.entries[i-1]
-- end
-- 
-- do
-- 	local function it(self, i)
-- 		if i >= 64 then
-- 			return nil
-- 		end
-- 		return i + 1, self:get(i)
-- 	end
-- 
-- 	function mg_lpm4Routes.__ipairs(self)
-- 		return it, self, 0
-- 	end
-- end
-- ----- Returns a routing table entry
-- ---- @return corresponding routing entry, if valid. false otherwise
-- --function mg_lpm4Routes.__index(self, k)
-- --	-- TODO: is this as fast as I hope it to be?
-- --  --self.hit_mask & (1<<(k-1))
-- --	if type(k) == "number" then
-- --    local hit = band(self.hit_mask, lshift(1,k-1)) ~= 0
-- --    return hit and self.entries[i-1]
-- --  else
-- --    --return self[k]
-- --    print("here")
-- --    return false
-- --  end
-- --end
-- 
-- 
-- ffi.metatype("struct mg_lpm4_routes", mg_lpm4Routes)

return mod
