---------------------------------
--- @file filter.lua
--- @brief Filter ...
--- @todo TODO docu
---------------------------------

local mod = {}

local dpdkc = require "dpdkc"
local device = require "device"
local ffi = require "ffi"
local dpdk = require "dpdk"
local mbitmask = require "bitmask"
local err = require "error"
local log = require "log"

mod.DROP = -1


local dev = device.__devicePrototype

local deviceDependent = {}
deviceDependent[device.PCI_ID_X540] = require "filter_ixgbe"
deviceDependent[device.PCI_ID_X520] = require "filter_ixgbe"
deviceDependent[device.PCI_ID_82599] = require "filter_ixgbe"

ffi.cdef[[

// used by the (undocumented) flow_type fields in filters
enum rte_flow_type {
	RTE_ETH_FLOW_UNKNOWN = 0,
	RTE_ETH_FLOW_RAW,
	RTE_ETH_FLOW_IPV4,
	RTE_ETH_FLOW_FRAG_IPV4,
	RTE_ETH_FLOW_NONFRAG_IPV4_TCP,
	RTE_ETH_FLOW_NONFRAG_IPV4_UDP,
	RTE_ETH_FLOW_NONFRAG_IPV4_SCTP,
	RTE_ETH_FLOW_NONFRAG_IPV4_OTHER,
	RTE_ETH_FLOW_IPV6,
	RTE_ETH_FLOW_FRAG_IPV6,
	RTE_ETH_FLOW_NONFRAG_IPV6_TCP,
	RTE_ETH_FLOW_NONFRAG_IPV6_UDP,
	RTE_ETH_FLOW_NONFRAG_IPV6_SCTP,
	RTE_ETH_FLOW_NONFRAG_IPV6_OTHER,
	RTE_ETH_FLOW_L2_PAYLOAD,
	RTE_ETH_FLOW_IPV6_EX,
	RTE_ETH_FLOW_IPV6_TCP_EX,
	RTE_ETH_FLOW_IPV6_UDP_EX,
	RTE_ETH_FLOW_MAX
};

enum rte_filter_type {
	RTE_ETH_FILTER_NONE = 0,
	RTE_ETH_FILTER_MACVLAN,
	RTE_ETH_FILTER_ETHERTYPE,
	RTE_ETH_FILTER_FLEXIBLE,
	RTE_ETH_FILTER_SYN,
	RTE_ETH_FILTER_NTUPLE,
	RTE_ETH_FILTER_TUNNEL,
	RTE_ETH_FILTER_FDIR,
	RTE_ETH_FILTER_HASH,
	RTE_ETH_FILTER_MAX
};

enum rte_filter_op {
	RTE_ETH_FILTER_NOP = 0,
	RTE_ETH_FILTER_ADD,
	RTE_ETH_FILTER_UPDATE,
	RTE_ETH_FILTER_DELETE,
	RTE_ETH_FILTER_FLUSH,
	RTE_ETH_FILTER_GET,
	RTE_ETH_FILTER_SET,
	RTE_ETH_FILTER_INFO,
	RTE_ETH_FILTER_STATS,
	RTE_ETH_FILTER_OP_MAX
};

enum rte_mac_filter_type {
	RTE_MAC_PERFECT_MATCH = 1,
	RTE_MACVLAN_PERFECT_MATCH,
	RTE_MAC_HASH_MATCH,
	RTE_MACVLAN_HASH_MATCH,
};

struct rte_eth_ethertype_filter {
	uint8_t mac_addr[6];
	uint16_t ether_type;
	uint16_t flags;
	uint16_t queue;
};

struct rte_eth_l2_flow {
	uint16_t ether_type;          /**< Ether type to match */
};

struct rte_eth_ipv4_flow {
	uint32_t src_ip;      /**< IPv4 source address to match. */
	uint32_t dst_ip;      /**< IPv4 destination address to match. */
};

struct rte_eth_udpv4_flow {
	struct rte_eth_ipv4_flow ip; /**< IPv4 fields to match. */
	uint16_t src_port;           /**< UDP source port to match. */
	uint16_t dst_port;           /**< UDP destination port to match. */
};

struct rte_eth_tcpv4_flow {
	struct rte_eth_ipv4_flow ip; /**< IPv4 fields to match. */
	uint16_t src_port;           /**< TCP source port to match. */
	uint16_t dst_port;           /**< TCP destination port to match. */
};

struct ether_addr {
	uint8_t addr_bytes[6];
};

/**
* A structure used to define the input for IPV4 SCTP flow
*/
struct rte_eth_sctpv4_flow {
	struct rte_eth_ipv4_flow ip; /**< IPv4 fields to match. */
	uint16_t src_port;           /**< SCTP source port to match. */
	uint16_t dst_port;           /**< SCTP destination port to match. */
	uint32_t verify_tag;         /**< Verify tag to match */
};

/**
* A structure used to define the input for IPV6 flow
*/
struct rte_eth_ipv6_flow {
	uint32_t src_ip[4];      /**< IPv6 source address to match. */
	uint32_t dst_ip[4];      /**< IPv6 destination address to match. */
};

/**
* A structure used to define the input for IPV6 UDP flow
*/
struct rte_eth_udpv6_flow {
	struct rte_eth_ipv6_flow ip; /**< IPv6 fields to match. */
	uint16_t src_port;           /**< UDP source port to match. */
	uint16_t dst_port;           /**< UDP destination port to match. */
};

/**
* A structure used to define the input for IPV6 TCP flow
*/
struct rte_eth_tcpv6_flow {
	struct rte_eth_ipv6_flow ip; /**< IPv6 fields to match. */
	uint16_t src_port;           /**< TCP source port to match. */
	uint16_t dst_port;           /**< TCP destination port to match. */
};

/**
* A structure used to define the input for IPV6 SCTP flow
*/
struct rte_eth_sctpv6_flow {
	struct rte_eth_ipv6_flow ip; /**< IPv6 fields to match. */
	uint16_t src_port;           /**< SCTP source port to match. */
	uint16_t dst_port;           /**< SCTP destination port to match. */
	uint32_t verify_tag;         /**< Verify tag to match */
};

/**
* A structure used to define the input for MAC VLAN flow
*/
struct rte_eth_mac_vlan_flow {
	struct ether_addr mac_addr;  /**< Mac address to match. */
};

/**
* Tunnel type for flow director.
*/
enum rte_eth_fdir_tunnel_type {
	RTE_FDIR_TUNNEL_TYPE_UNKNOWN = 0,
	RTE_FDIR_TUNNEL_TYPE_NVGRE,
	RTE_FDIR_TUNNEL_TYPE_VXLAN,
};

/**
* A structure used to define the input for tunnel flow, now its VxLAN or
* NVGRE
*/
struct rte_eth_tunnel_flow {
	enum rte_eth_fdir_tunnel_type tunnel_type; /**< Tunnel type to match. */
	uint32_t tunnel_id;                        /**< Tunnel ID to match. TNI, VNI... */
	struct ether_addr mac_addr;                /**< Mac address to match. */
};

union rte_eth_fdir_flow {
	struct rte_eth_l2_flow     l2_flow;
	struct rte_eth_udpv4_flow  udp4_flow;
	struct rte_eth_tcpv4_flow  tcp4_flow;
	struct rte_eth_sctpv4_flow sctp4_flow;
	struct rte_eth_ipv4_flow   ip4_flow;
	struct rte_eth_udpv6_flow  udp6_flow;
	struct rte_eth_tcpv6_flow  tcp6_flow;
	struct rte_eth_sctpv6_flow sctp6_flow;
	struct rte_eth_ipv6_flow   ipv6_flow;
	struct rte_eth_mac_vlan_flow mac_vlan_flow;
	struct rte_eth_tunnel_flow   tunnel_flow;
};

struct rte_eth_fdir_flow_ext {
	uint16_t vlan_tci;
	uint8_t flexbytes[16];
	/**< It is filled by the flexible payload to match. */
	uint8_t is_vf;   /**< 1 for VF, 0 for port dev */
	uint16_t dst_id; /**< VF ID, available when is_vf is 1*/
};

struct rte_eth_fdir_input {
	uint16_t flow_type;
	union rte_eth_fdir_flow flow;
	/**< Flow fields to match, dependent on flow_type */
	struct rte_eth_fdir_flow_ext flow_ext;
	/**< Additional fields to match */
};

/**
* Behavior will be taken if FDIR match
*/
enum rte_eth_fdir_behavior {
	RTE_ETH_FDIR_ACCEPT = 0,
	RTE_ETH_FDIR_REJECT,
	RTE_ETH_FDIR_PASSTHRU,
};

/**
* Flow director report status
* It defines what will be reported if FDIR entry is matched.
*/
enum rte_eth_fdir_status {
	RTE_ETH_FDIR_NO_REPORT_STATUS = 0, /**< Report nothing. */
	RTE_ETH_FDIR_REPORT_ID,            /**< Only report FD ID. */
	RTE_ETH_FDIR_REPORT_ID_FLEX_4,     /**< Report FD ID and 4 flex bytes. */
	RTE_ETH_FDIR_REPORT_FLEX_8,        /**< Report 8 flex bytes. */
};


struct rte_eth_fdir_action {
	uint16_t rx_queue;        /**< Queue assigned to if FDIR match. */
	enum rte_eth_fdir_behavior behavior;     /**< Behavior will be taken */
	enum rte_eth_fdir_status report_status;  /**< Status report option */
	uint8_t flex_off;
	/**< If report_status is RTE_ETH_FDIR_REPORT_ID_FLEX_4 or
	RTE_ETH_FDIR_REPORT_FLEX_8, flex_off specifies where the reported
	flex bytes start from in flexible payload. */
};

struct rte_eth_fdir_filter {
	uint32_t soft_id;
	/**< ID, an unique value is required when deal with FDIR entry */
	struct rte_eth_fdir_input input;    /**< Input set */
	struct rte_eth_fdir_action action;  /**< Action taken when match */
};


int rte_eth_dev_filter_ctrl(uint8_t port_id, enum rte_filter_type filter_type, enum rte_filter_op filter_op, void * arg);
]]

local RTE_ETHTYPE_FLAGS_MAC		= 1
local RTE_ETHTYPE_FLAGS_DROP	= 2

local C = ffi.C

function dev:l2Filter(etype, queue)
	if type(queue) == "table" then
		if queue.dev.id ~= self.id then
			log:fatal("Queue must belong to the device being configured")
		end
		queue = queue.qid
	end
	local flags = 0
	if queue == self.DROP then
		flags = RTE_ETHTYPE_FLAGS_DROP
	end
	local filter = ffi.new("struct rte_eth_ethertype_filter", { ether_type = etype, flags = 0, queue = queue })
	local ok = C.rte_eth_dev_filter_ctrl(self.id, C.RTE_ETH_FILTER_ETHERTYPE, C.RTE_ETH_FILTER_ADD, filter)
	if ok ~= 0 and ok ~= -38 then -- -38 means duplicate filter for some reason
		log:warn("l2 filter error: " .. ok)
	end
end

--- Installs a 5tuple filter on the device.
---  Matching packets will be redirected into the specified rx queue
---  NOTE: this is currently only tested for X540 NICs, and will probably also
---  work for 82599 and other ixgbe NICs. Use on other NICs might result in
---  undefined behavior.
--- @param filter A table describing the filter. Possible fields are
---   src_ip    :  Sourche IPv4 Address
---   dst_ip    :  Destination IPv4 Address
---   src_port  :  Source L4 port
---   dst_port  :  Destination L4 port
---   l4protocol:  L4 Protocol type
---                supported protocols: ip.PROTO_ICMP, ip.PROTO_TCP, ip.PROTO_UDP
---                If a non supported type is given, the filter will only match on
---                protocols, which are not supported.
---  All fields are optional.
---  If a field is not present, or nil, the filter will ignore this field when
---  checking for a match.
--- @param queue RX Queue, where packets, matching this filter will be redirected
--- @param priority optional (default = 1) The priority of this filter rule.
---  7 is the highest priority and 1 the lowest priority.
function dev:addHW5tupleFilter(filter, queue, priority)
  fun = deviceDependent[self:getPciId()].addHW5tupleFilter
  if fun then
    return fun(self, filter, queue, priority)
  else
    log:fatal("addHW5tupleFilter not supported, or not yet implemented for this device")
  end
end

--- Filter PTP time stamp packets by inspecting the PTP version and type field.
--- Packets with PTP version 2 are matched with this filter.
--- @param queue
--- @param offset the offset of the PTP version field
--- @param ntype the PTP type to look for, default = 0
--- @param ver the PTP version to look for, default = 2
function dev:filterTimestamps(queue, offset, ntype, ver)
	-- TODO: dpdk only allows to change this at init time
	-- however, I think changing the flex-byte offset field in the FDIRCTRL register can be changed at run time here
	-- (as the fdir table needs to be cleared anyways which is the only precondition for changing this)
	if type(queue) == "table" then
		queue = queue.qid
	end
	offset = offset or 21
	if offset ~= 21 then
		log:fatal("Other offsets are not yet supported")
	end
	mtype = mtype or 0
	ver = ver or 2
	local filter = ffi.new("struct rte_eth_fdir_filter", {
		soft_id = 1,
		input = {
			-- explicitly only matching UDP flows here would be better
			-- however, this is no longer possible with the dpdk 2.x filter api :(
			-- it can no longer match only the protocol type while ignoring port numbers...
			-- (and reconfiguring the filter for ports all the time is annoying)
			flow_type = dpdkc.RTE_ETH_FLOW_L2_PAYLOAD,--dpdkc.RTE_ETH_FLOW_IPV4,
			flow = {
				udp4_flow = {
					ip = {
						src_ip = 0,
						dst_ip = 0,
					},
					src_port = 0,
					dst_port = 0,
				}
			},
			flow_ext = {
				vlan_tci = 0,
				flexbytes = { mtype, ver },
				is_vf = 0,
				dst_id = 0,
			},
		},
		action = {
			rx_queue = queue
		},
	})
	local ok = C.rte_eth_dev_filter_ctrl(self.id, C.RTE_ETH_FILTER_FDIR, C.RTE_ETH_FILTER_ADD, filter)
	if ok ~= 0 then
		log:warn("fdir filter error: " .. ok)
	end
end


-- FIXME: port to DPDK 2.x
ffi.cdef [[
struct mg_5tuple_rule {
    uint8_t proto;
    uint32_t ip_src;
    uint8_t ip_src_prefix;
    uint32_t ip_dst;
    uint8_t ip_dst_prefix;
    uint16_t port_src;
    uint16_t port_src_range;
    uint16_t port_dst;
    uint16_t port_dst_range;

};

struct rte_acl_ctx * mg_5tuple_create_filter(int socket_id, uint32_t num_rules);
void mg_5tuple_destruct_filter(struct rte_acl_ctx * acl);
int mg_5tuple_add_rule(struct rte_acl_ctx * acx, struct mg_5tuple_rule * mgrule, int32_t priority, uint32_t category_mask, uint32_t value);
int mg_5tuple_build_filter(struct rte_acl_ctx * acx, uint32_t num_categories);
int mg_5tuple_classify_burst(
    struct rte_acl_ctx * acx,
    struct rte_mbuf **pkts,
    struct mg_bitmask* pkts_mask,
    uint32_t num_categories,
    uint32_t num_real_categories,
    struct mg_bitmask** result_masks,
    uint32_t ** result_entries
    );
uint32_t mg_5tuple_get_results_multiplier();
]]

local mg_filter_5tuple = {}
mod.mg_filter_5tuple = mg_filter_5tuple
mg_filter_5tuple.__index = mg_filter_5tuple

--- Creates a new 5tuple filter / packet classifier
--- @param socket optional (default: socket of calling thread), CPU socket, where memory for the filter should be allocated.
--- @param acx experimental use only. should be nil.
--- @param numCategories number of categories, this filter should support
--- @param maxNRules optional (default = 10), maximum number of rules.
--- @return a wrapper table for the created filter
function mod.create5TupleFilter(socket, acx, numCategories, maxNRules)
  socket = socket or select(2, dpdk.getCore())
  maxNRules = maxNRules or 10

  local category_multiplier = ffi.C.mg_5tuple_get_results_multiplier()

  local rest = numCategories % category_multiplier

  local numBlownCategories = numCategories
  if(rest ~= 0) then
    numBlownCategories = numCategories + category_multiplier - rest
  end

  local result =  setmetatable({
    acx = acx or ffi.gc(ffi.C.mg_5tuple_create_filter(socket, maxNRules), function(self)
      -- FIXME: why is destructor never called?
      log:debug("5tuple garbage")
      ffi.C.mg_5tuple_destruct_filter(self)
    end),
    built = false,
    nrules = 0,
    numCategories = numBlownCategories,
    numRealCategories = numCategories,
    out_masks = ffi.new("struct mg_bitmask*[?]", numCategories),
    out_values = ffi.new("uint32_t*[?]", numCategories)
  }, mg_filter_5tuple)

  for i = 1,numCategories do
    result.out_masks[i-1] = nil
  end
  return result
end


--- Bind an array of result values to a filter category.
--- One array of values can be boun to multiple categories. After classification
--- it will contain mixed values of all categories it was bound to.
--- @param values Array of values to be bound to a category. May also be a number. In this case
---  a new Array will be allocated and bound to the specified category.
--- @param category optional (default = bind the specified array to all not yet bound categories),
---  The category the array should be bound to
--- @return the array, which was bound
function mg_filter_5tuple:bindValuesToCategory(values, category)
  if type(values) == "number" then
    values = ffi.new("uint32_t[?]", values)
  end
  if not category then
    -- bind bitmask to all categories, which do not yet have an associated bitmask
    for i = 1,self.numRealCategories do
      if (self.out_values[i-1] == nil) then
        log:debug("Assigned default at category " .. tostring(i))
        self.out_values[i-1] = values
      end
    end
  else
    log:debug("Assigned bitmask to category " .. tostring(category))
    self.out_values[category-1] = values
  end
  return values
end

--- Bind a BitMask to a filter category.
--- On Classification the corresponding bits in the bitmask are set, when a rule
--- matches a packet, for the corresponding category.
--- One Bitmask can be bound to multiple categories. The result will be a bitwise OR
--- of the Bitmasks, which would be filled for each category.
--- @param bitmask Bitmask to be bound to a category. May also be a number. In this case
---  a new BitMask will be allocated and bound to the specified category.
--- @param category optional (default = bind the specified bitmask to all not yet bound categories),
---  The category the bitmask should be bound to
--- @return the bitmask, which was bound
function mg_filter_5tuple:bindBitmaskToCategory(bitmask, category)
  if type(bitmask) == "number" then
    bitmask = mbitmask.createBitMask(bitmask)
  end
  if not category then
    -- bind bitmask to all categories, which do not yet have an associated bitmask
    for i = 1,self.numRealCategories do
      if (self.out_masks[i-1] == nil) then
        log:debug("Assigned default at category " .. tostring(i))
        self.out_masks[i-1] = bitmask.bitmask
      end
    end
  else
    log:debug("Assigned bitmask to category " .. tostring(category))
    self.out_masks[category-1] = bitmask.bitmask
  end
  return bitmask
end


--- Allocates memory for one 5 tuple rule
--- @return ctype object "struct mg_5tuple_rule"
function mg_filter_5tuple:allocateRule()
  return ffi.new("struct mg_5tuple_rule")
end

--- Adds a rule to the filter
--- @param rule the rule to be added (ctype "struct mg_5tuple_rule")
--- @priority priority of the rule. Higher number -> higher priority
--- @category_mask bitmask for the categories, this rule should apply
--- @value 32bit integer value associated with this rule. Value is not allowed to be 0
function mg_filter_5tuple:addRule(rule, priority, category_mask, value)
  if(value == 0) then
    log:fatal("Adding a rule with a 0 value is not allowed")
  end
  self.buit = false
  return ffi.C.mg_5tuple_add_rule(self.acx, rule, priority, category_mask, value)
end

--- Builds the filter with the currently added rules. Should be executed after adding rules
--- @param optional (default = number of Categories, set at 5tuple filter creation time) numCategories maximum number of categories, which are in use.
function mg_filter_5tuple:build(numCategories)
  numCategories = numCategories or self.numRealCategories
  self.built = true
  --self.numCategories = numCategories
  return ffi.C.mg_5tuple_build_filter(self.acx, numCategories)
end

--- Perform packet classification for a burst of packets
--- Will do memory violation, when Masks or Values are not correctly bound to categories.
--- @param pkts Array of mbufs. Mbufs should contain valid IPv4 packets with a
---  normal ethernet header (no VLAN tags). A L4 Protocol header has to be
---  present, to avoid reading at invalid memory address. -- FIXME: check if this is true
--- @param inMask bitMask, specifying on which packets the filter should be applied
--- @return 0 on successfull completion.
function mg_filter_5tuple:classifyBurst(pkts, inMask)
  if not self.built then
    log:warn("New rules have been added without building the filter!")
  end
  --numCategories = numCategories or self.numCategories
  return ffi.C.mg_5tuple_classify_burst(self.acx, pkts.array, inMask.bitmask, self.numCategories, self.numRealCategories, self.out_masks, self.out_values)
end
return mod

