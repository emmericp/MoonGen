local ffi = require "ffi"

require "utils"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"

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

int mg_lpm_table_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries);


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



int printf(const char *fmt, ...);

]]


local mod = {}

local mg_lpm4Table = {}
--- Create a new LPM lookup table.
-- @param socket optional (default = socket of the calling thread), CPU socket, where memory for the table should be allocated.
function mod:create_lpm4Table(socket)
  socket = socket or select(2, dpdk.getCore())
    -- configure parameters for the LPM table
  local params = ffi.new("struct rte_table_lpm_params")
  params.n_rules = 1000
  params.entry_unique_size = 5
  params.offset = 0
  return setmetatable({
    table = ffi.C.mg_lpm_table_create(params, socket, ffi.sizeof("struct mg_lpm_table_entry"))
  }, mg_lpm4Table)
end

--- Add an entry to a Table
--  @param addr IPv4 network address of the destination network.
--  @param depth number of significant bits of the destination network address
--  @param entry routing table entry
--  @return true if entry was added without error
function mg_lpm4Table:add_entry(addr, depth, entry)
  return 0 == ffi.C.mg_lpm_table_entry_add_simple(self.table, addr, depth, entry)
end

--- Constructs a LPM table entry for IPv4
-- @return LPM table entry of ctype "struct mg_lpm4_table_entry"
function mod:new_lpm4_table_entry(ip_next_hop, interface, mac_next_hop)
  entry = ffi.new("struct mg_lpm4_table_entry")
  entry.ip_next_hop = ip_next_hop
  entry.interface = interface
  entry.mac_next_hop = mac_next_hop
  return entry
end



--local mg_lpm4Entry = {}
--mg_lpm4Entry.__index = mg_lpm4Entry
--function mg_
--
--ffi.metatype("struct mg_lpm4_table_entry", mg_lpm4Entry)
local 
