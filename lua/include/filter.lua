local mod = {}

local dpdkc = require "dpdkc"
local device = require "device"
local ffi = require "ffi"

mod.DROP = -1

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



local dev = device.__devicePrototype

function dev:l2Filter(etype, queue)
	if type(queue) == "table" then
		if queue.dev ~= self then
			error("Queue must belong to the device being configured")
		end
		queue = queue.qid
	end
	-- TODO: support for other NICs
	if queue == -1 then
		queue = 63
	end
	dpdkc.write_reg32(self.id, ETQF[1], bit.bor(ETQF_FILTER_ENABLE, etype))
	dpdkc.write_reg32(self.id, ETQS[1], bit.bor(ETQS_QUEUE_ENABLE, bit.lshift(queue, ETQS_RX_QUEUE_OFFS)))
end

-- fdir support for layer 3/4 filters

-- todo: IP/port filter

--- Filter PTP time stamp packets by inspecting the PTP version and type field.
-- Packets with PTP version 2 are matched with this filter.
-- @arg offset the offset of the PTP version field
-- @arg mtype the PTP type to look for, default = 0
-- @arg ver the PTP version to look for, default = 2
function dev:filterTimestamps(queue, offset, ntype, ver)
	-- TODO: dpdk only allows to change this at init time
	-- however, I think changing the flex-byte offset field in the FDIRCTRL register can be changed at run time here
	-- (as the fdir table needs to be cleared anyways which is the only precondition for changing this)
	if type(queue) == "table" then
		queue = queue.qid
	end
	offset = offset or 21
	if offset ~= 21 then
		error("other offsets are not yet supported")
	end
	mtype = mtype or 0
	ver = ver or 2
	local value = value or bit.lshift(ver, 8) + mtype
	local filter = ffi.new("struct rte_fdir_filter")
	filter.flex_bytes = value
	local mask = ffi.new("struct rte_fdir_masks")
	mask.only_ip_flow = 1
	mask.flexbytes = 1
	dpdkc.rte_eth_dev_fdir_set_masks(self.id, mask)
	dpdkc.rte_eth_dev_fdir_add_perfect_filter(self.id, filter, 1, queue, 0)
end

return mod

