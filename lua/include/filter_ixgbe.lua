---------------------------------
--- @file filter_ixgbe.lua
--- @brief Filter for IXGBE ...
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

local ETQF_BASE			= 0x00005128
local ETQS_BASE			= 0x0000EC00

local ETQF_FILTER_ENABLE	= bit.lshift(1, 31)
local ETQF_IEEE_1588_TIME_STAMP	= bit.lshift(1, 30)

local ETQS_RX_QUEUE_OFFS	= 16
local ETQS_QUEUE_ENABLE		= bit.lshift(1, 31)

local ETQF = {}
for i = 0, 7 do
	ETQF[i] = ETQF_BASE + 4 * i
end
local ETQS = {}
for i = 0, 7 do
	ETQS[i] = ETQS_BASE + 4 * i
end

ffi.cdef[[
struct rte_5tuple_filter {
	uint32_t dst_ip;         /**< destination IP address in big endian. */
	uint32_t src_ip;         /**< source IP address in big endian. */
	uint16_t dst_port;       /**< destination port in big endian. */
	uint16_t src_port;       /**< source Port big endian. */
	uint8_t protocol;        /**< l4 protocol. */
	uint8_t tcp_flags;       /**< tcp flags. */
	uint16_t priority;       /**< seven evels (001b-111b), 111b is highest,
				      used when more than one filter matches. */
	uint8_t dst_ip_mask:1,   /**< if mask is 1b, do not compare dst ip. */
		src_ip_mask:1,   /**< if mask is 1b, do not compare src ip. */
		dst_port_mask:1, /**< if mask is 1b, do not compare dst port. */
		src_port_mask:1, /**< if mask is 1b, do not compare src port. */
		protocol_mask:1; /**< if mask is 1b, do not compare protocol. */
};

int rte_eth_dev_add_5tuple_filter 	( 	uint8_t  	port_id,
		uint16_t  	index,
		struct rte_5tuple_filter *  	filter,
		uint16_t  	rx_queue 
	);
int
mg_5tuple_add_HWfilter_ixgbe(uint8_t port_id, uint16_t index,
			struct rte_5tuple_filter *filter, uint16_t rx_queue);
]]

function mod.l2Filter(dev, etype, queue)
	if queue == -1 then
		queue = 127
	end
	dpdkc.write_reg32(dev.id, ETQF[1], bit.bor(ETQF_FILTER_ENABLE, etype))
	dpdkc.write_reg32(dev.id, ETQS[1], bit.bor(ETQS_QUEUE_ENABLE, bit.lshift(queue, ETQS_RX_QUEUE_OFFS)))
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
function mod.addHW5tupleFilter(dev, filter, queue, priority)
  local sfilter = ffi.new("struct rte_5tuple_filter")
  sfilter.src_ip_mask   = (filter.src_ip      == nil) and 1 or 0
  sfilter.dst_ip_mask   = (filter.dst_ip      == nil) and 1 or 0
  sfilter.src_port_mask = (filter.src_port    == nil) and 1 or 0
  sfilter.dst_port_mask = (filter.dst_port    == nil) and 1 or 0
  sfilter.protocol_mask = (filter.l4protocol  == nil) and 1 or 0

  sfilter.priority = priority or 1
  if(sfilter.priority > 7 or sfilter.priority < 1) then
    log:fatal("Filter priority has to be a number from 1 to 7")
    return
  end

  sfilter.src_ip    = filter.src_ip     or 0
  sfilter.dst_ip    = filter.dst_ip     or 0
  sfilter.src_port  = filter.src_port   or 0
  sfilter.dst_port  = filter.dst_port   or 0
  sfilter.protocol  = filter.l4protocol or 0
  --if (filter.l4protocol) then
  --  print "[WARNING] Protocol filter not yet fully implemented and tested"
  --end

  if dev.filters5Tuple == nil then
    dev.filters5Tuple = {}
    dev.filters5Tuple.n = 0
  end
  dev.filters5Tuple[dev.filters5Tuple.n] = sfilter
  local idx = dev.filters5Tuple.n
  dev.filters5Tuple.n = dev.filters5Tuple.n + 1

  local state
  if (dev:getPciId() == device.PCI_ID_X540) then
    -- TODO: write a proper patch for dpdk
    state = ffi.C.mg_5tuple_add_HWfilter_ixgbe(dev.id, idx, sfilter, queue.qid)
  else
    state = ffi.C.rte_eth_dev_add_5tuple_filter(dev.id, idx, sfilter, queue.qid)
  end

  if (state ~= 0) then
    log:fatal("Filter not successfully added: %s", err.getstr(-state))
  end

  return idx
end

return mod
