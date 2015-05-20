local ffi = require "ffi"

--require "utils"
local band, lshift = bit.band, bit.lshift
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local serpent = require "Serpent"
--local burst = require "burst"

ffi.cdef [[
// table wrapper
void* mg_lpm_table_create(void *params, int socket_id, uint32_t entry_size);

int mg_lpm_table_free(void *table);

int mg_lpm_table_entry_add_simple(
    void *table,
    uint32_t ip,
    uint8_t depth,
    void *entry);

int mg_lpm_table_entry_delete(
	void *table,
	void *key,
	int *key_found,
	void *entry);

//int mg_lpm_table_lookup(
//	void *table,
//	struct rte_mbuf **pkts,
//	uint64_t pkts_mask,
//	uint64_t *lookup_hit_mask,
//	void **entries);
int mg_lpm_table_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	//uint64_t *lookup_hit_mask,
  struct mg_lpm4_routes * routes);

///////////////////////////////////////////////////////////////////
/** LPM table parameters */

struct rte_table_lpm_params {
	uint32_t n_rules;
	uint32_t entry_unique_size;
	uint32_t offset;
};

struct rte_table_lpm_key {
	uint32_t ip;
	uint8_t depth;
};

struct mg_lpm4_table_entry {
  uint32_t ip_next_hop;
  uint8_t interface;
  struct mac_address mac_next_hop;
};

struct mg_lpm4_routes {
  struct mg_lpm4_table_entry entries[64];
  uint64_t hit_mask;
};

int printf(const char *fmt, ...);

]]


local mod = {}

local mg_lpm4Table = {}
mg_lpm4Table.__index = mg_lpm4Table

--- Create a new LPM lookup table.
-- @param socket optional (default = socket of the calling thread), CPU socket, where memory for the table should be allocated.
-- @return the table handler
function mod.createLpm4Table(socket, table)
  -- FIXME: understand getCore and select
  socket = socket or select(2, dpdk.getCore())
    -- configure parameters for the LPM table
  local params = ffi.new("struct rte_table_lpm_params")
  params.n_rules = 1000
  params.entry_unique_size = 5
  --params.offset = 128 + 27+4
  params.offset = 27+4
  return setmetatable({
    table = table or ffi.C.mg_lpm_table_create(params, socket, ffi.sizeof("struct mg_lpm4_table_entry"))
  }, mg_lpm4Table)
end

--- Free the LPM Table
-- @return 0 on success, error code otherwise
function mg_lpm4Table:destruct()
  return ffi.C.mg_lpm_table_free(self.table)
end

--- Add an entry to a Table
-- @param addr IPv4 network address of the destination network.
-- @param depth number of significant bits of the destination network address
-- @param entry routing table entry
-- @return true if entry was added without error
function mg_lpm4Table:addEntry(addr, depth, entry)
  return 0 == ffi.C.mg_lpm_table_entry_add_simple(self.table, addr, depth, entry)
end

--- Perform IPv4 route lookup for a burst of packets
-- @param packets Array of mbufs (bufArray), for which the lookup will be performed
-- @param mask optional (default = all packets), bitmask, for which packets the lookup should be performed
-- @param routes Preallocated routing entry list (mg_lpmRoutes)
function mg_lpm4Table:lookupBurst(packets, mask, routes)
  --local bmask = mask or lshift(1,packets.size)-1
  --local bmask = lshift(1,packets.size)-1
  print("here1")
  mask = mask or lshift(1,packets.size) - 1
  print("here2")
  return ffi.C.mg_lpm_table_lookup(self.table, packets.array, mask, routes)
end

function mg_lpm4Table:__serialize()
	return "require 'lpm'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('lpm')"), true
end
--- Constructs a LPM table entry for IPv4
-- @return LPM table entry of ctype "struct mg_lpm4_table_entry"
function mod.constructLpm4TableEntry(ip_next_hop, interface, mac_next_hop)
  entry = ffi.new("struct mg_lpm4_table_entry")
  entry.ip_next_hop = ip_next_hop
  entry.interface = interface
  entry.mac_next_hop = mac_next_hop
  return entry
end

function mod.allocateLpm4Routes()
  return ffi.new("struct mg_lpm4_routes")
end

local mg_lpm4Routes = {}
mg_lpm4Routes.__index = mg_lpm4Routes

----- Returns a routing table entry
---- @return corresponding routing entry, if valid. false otherwise
function mg_lpm4Routes:get(n)
  local hit = band(self.hit_mask, lshift(1,n-1)) ~= 0
  return hit and self.entries[i-1]
end

do
	local function it(self, i)
		if i >= 64 then
			return nil
		end
		return i + 1, self:get(i)
	end

	function mg_lpm4Routes.__ipairs(self)
		return it, self, 0
	end
end
----- Returns a routing table entry
---- @return corresponding routing entry, if valid. false otherwise
--function mg_lpm4Routes.__index(self, k)
--	-- TODO: is this as fast as I hope it to be?
--  --self.hit_mask & (1<<(k-1))
--	if type(k) == "number" then
--    local hit = band(self.hit_mask, lshift(1,k-1)) ~= 0
--    return hit and self.entries[i-1]
--  else
--    --return self[k]
--    print("here")
--    return false
--  end
--end


ffi.metatype("struct mg_lpm4_routes", mg_lpm4Routes)

return mod
