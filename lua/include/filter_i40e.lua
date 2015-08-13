---------------------------------
--- @file filter_i40e.lua
--- @brief Filter for I40E ...
--- @todo TODO docu
---------------------------------

local mod = {}

local dpdkc = require "dpdkc"
local device = require "device"
local ffi = require "ffi"
local dpdk = require "dpdk"


--- @todo FIXME: this function is highly device dependent
function mod.l2Filter(dev, etype, queue)
	printf("WARNING: l2 filter is not yet supported")
end

return mod
