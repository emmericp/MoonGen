local proto = require "proto.proto"

local dynvar = {}
dynvar.__index = dynvar

local _aliases = {
	udpSrc = proto.udp.metatype.setSrcPort, udpDst = proto.udp.metatype.setDstPort,
	tcpSrc = proto.tcp.metatype.setSrcPort, tcpDst = proto.tcp.metatype.setDstPort,
	ethSrc = proto.eth.default.metatype.setSrc, ethDst = proto.eth.default.metatype.setDst,
	ethVlan = proto.eth.vlan.metatype.setVlanTag,
	ethinnerVlanTag = proto.eth.qinq.metatype.setInnerVlanTag,
	ethouterVlanId = proto.eth.qinq.metatype.setOuterVlanTag,
	ethouterVlanTag = proto.eth.qinq.metatype.setOuterVlanTag,
}
local function _find_setter(pkt, var)
	local alias = _aliases[pkt .. var]
	if alias then
		return alias
	end

	return proto[pkt].metatype["set" .. var]
end

local function _new_dynvar(pkt, var, func)
	local self = { pkt = pkt, var = var, func = func }
	self.applyfn = _find_setter(pkt, var)
	assert(self.applyfn, pkt .. var)
	self.value = func()

	return setmetatable(self, dynvar)
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
dynvars.__index, dv_final.__index = dynvars, dv_final

function dynvars.new()
	local self = {
		index = {}, count = 0
	}
	return setmetatable(self, dynvars)
end

local function _add_dv(self, index, dv)
	table.insert(self, dv)
	self.index[index] = dv
	self.count = self.count + 1
end

function dynvars:add(pkt, var, func)
	local dv = _new_dynvar(pkt, var, func)
	_add_dv(self, pkt .. var, dv)
	return dv
end

function dynvars:inherit(other, fillTbl)
	for i,v in pairs(other.index) do
		local ftIndex = v.pkt .. v.var
		if not self.index[i] and not fillTbl[ftIndex] then
			_add_dv(self, i, v)
		end
	end
end

function dynvars:finalize()
	setmetatable(self, dv_final)
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
