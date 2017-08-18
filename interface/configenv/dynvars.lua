local proto = require "proto.proto"

local dynvar = {}
local _mt_dynvar = { __index = dynvar }

local _aliases = {
	udp_src = "setSrcPort", udp_dst = "setDstPort",
	tcp_src = "setSrcPort", tcp_dst = "setDstPort",
}
local function _find_setter(pkt, var)
	local alias = _aliases[pkt .. "_" .. var]
	if alias then
		return proto[pkt].metatype[alias]
	end

	return proto[pkt].metatype["set" .. string.upper(string.sub(var, 1, 1)) .. string.sub(var, 2)]
end

local function _new_dynvar(pkt, var, func)
	local self = { pkt = pkt, var = var, func = func }
	self.applyfn = _find_setter(pkt, var)
	assert(self.applyfn, pkt .. "_" .. var)
	self.value = func() -- NOTE arp will execute in master

	return setmetatable(self, _mt_dynvar)
end

function dynvar:update()
	local v = self.func()
	self.value = v
	return v
end

function dynvar:apply(pkt)
	self.applyfn(pkt[self.pkt], self.value)
end

function dynvar:updateApply(pkt)
	dynvar.update(self)
	self.applyfn(pkt[self.pkt], self.value)
end

local dynvars, dv_final = {}, {}
local _mt_dynvars = { __index = dynvars }
local _mt_dv_final = { __index = dv_final }

function dynvars.new()
	local self = {
		index = {}, count = 0
	}
	return setmetatable(self, _mt_dynvars)
end

local function _add_dv(self, index, dv)
	table.insert(self, dv)
	self.index[index] = dv
	self.count = self.count + 1
end

function dynvars:add(pkt, var, func)
	local dv = _new_dynvar(pkt, var, func)
	_add_dv(self, pkt .. "_" .. var, dv)
	return dv
end

function dynvars:inherit(other)
	for i,v in pairs(other.index) do
		if not self.index[i] then
			_add_dv(self, i, v)
		end
	end
end

function dynvars:finalize()
	setmetatable(self, _mt_dv_final)
end

function dv_final:updateAll()
	for i = 1, self.count do
		dynvar.update(self[i])
	end
end

function dv_final:applyAll(pkt)
	for i = 1, self.count do
		dynvar.apply(self[i], pkt)
	end
end

function dv_final:updateApplyAll(pkt)
	for i = 1, self.count do
		dynvar.updateApply(self[i], pkt)
	end
end

return dynvars
