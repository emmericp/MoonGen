---------------------------------
--- @file lpm.lua
--- @brief Longest Prefix Matching ...
--- @todo TODO docu
---------------------------------

local ffi = require "ffi"

--require "utils"
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local serpent = require "Serpent"
local log = require "log"
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

int mg_table_lpm_apply_route(
	struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
	void **entries,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size);

]]


local mod = {}

local mg_lpm4Table = {}
mod.mg_lpm4Table = mg_lpm4Table
mg_lpm4Table.__index = mg_lpm4Table

--- Create a new LPM lookup table.
--- @param socket optional (default = socket of the calling thread), CPU socket, where memory for the table should be allocated.
--- @return the table handler
function mod.createLpm4Table(socket, table, entry_ctype)
  socket = socket or select(2, dpdk.getCore())
    -- configure parameters for the LPM table
  local params = ffi.new("struct rte_table_lpm_params")
  params.n_rules = 1000
  params.entry_unique_size = 5
  --params.offset = 128 + 27+4
  params.offset = 128+ 14 + 12+4
  return setmetatable({
    table = table or ffi.gc(ffi.C.mg_table_lpm_create(params, socket, ffi.sizeof(entry_ctype)), function(self)
      -- FIXME: why is destructor never called?
      log:debug("lpm garbage")
      ffi.C.mg_table_lpm_free(self)
    end),
    entry_ctype = entry_ctype
  }, mg_lpm4Table)
end

-- --- Free the LPM Table
-- --- @return 0 on success, error code otherwise
-- function mg_lpm4Table:destruct()
--   return ffi.C.mg_table_lpm_free(self.table)
-- end

--- Add an entry to a Table
--- @param addr IPv4 network address of the destination network.
--- @param depth number of significant bits of the destination network address
--- @param entry routing table entry (will be copied)
--- @return true if entry was added without error
function mg_lpm4Table:addEntry(addr, depth, entry)
  return 0 == ffi.C.mg_table_entry_add_simple(self.table, addr, depth, entry)
end

--- Perform IPv4 route lookup for a burst of packets
--- This should not be used for single packet lookup, as ist brings
--- a significant penalty for bursts <<64
--- @param packets Array of mbufs (bufArray), for which the lookup will be performed
--- @param mask optional (default = all packets), bitmask, for which packets the lookup should be performed
--- @param hitMask Bitmask, where the routed packets are flagged
--- with one. This may be the same Bitmask as passed in the mask
--- parameter, in this case not routed packets will be cleared in
--- the bitmask.
--- @param entries Preallocated routing entry Pointers
function mg_lpm4Table:lookupBurst(packets, mask, hitMask, entries)
  -- FIXME: I feel uneasy about this cast, should this cast not be
  --  done implicitly?
  return ffi.C.mg_table_lpm_lookup_big_burst(self.table, packets.array, mask.bitmask, hitMask.bitmask, ffi.cast("void **",entries.array))
end

function mg_lpm4Table:__serialize()
	return "require 'lpm'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('lpm').mg_lpm4Table"), true
end

--- Allocates an LPM table entry
--- @return The newly allocated entry
function mg_lpm4Table:allocateEntry()
  return ffi.new(self.entry_ctype)
end

local mg_lpm4EntryPtrs = {}

--- Allocates an array of pointers to routing table entries
--- This is used during burst lookup, to store references to the
--- result entries.
--- @param n Number of entry pointers
--- @return Wrapper table around the allocated array
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

function mod.applyRoute(pkts, mask, entries, entryOffset)
  entryOffset = entryOffset or 1
  return ffi.C.mg_table_lpm_apply_route(pkts.array, mask.bitmask, ffi.cast("void **", entries.array), entryOffset, 128, 6)
end

--- FIXME: this should not be in LPM module. but where?
--- Decrements the IP TTL field of all masked packets by one.
---  out_mask masks the successfully decremented packets (TTL did not reach zero).
function mod.decrementTTL(pkts, in_mask, out_mask, ipv4)
  ipv4 = ipv4 == nil or ipv4
  if ipv4 then
    -- TODO: C implementation might be faster...
    for i, pkt in ipairs(pkts) do
      if in_mask[i] then
        local ipkt = pkt:getIPPacket()
        local ttl = ipkt.ip4:getTTL()
        ttl = ttl - 1;
        ipkt.ip4:setTTL(ttl)
        if(ttl ~= 0)then
          out_mask[i] = 1 
        else
          out_mask[i] = 0
        end
      else
        out_mask[i] = 0
      end
    end
  else
    log:fatal("TTL decrement for ipv6 not yet implemented")
  end
end

return mod
