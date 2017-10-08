local packet = require "packet"
local ffi    = require "ffi"

local dependencies = require "dependencies"

local Dynvars = require "flow.dynvars"

local Packet = {}
Packet.__index = Packet

ffi.cdef[[
	struct test_packet_t {};
]]

local test_packet = ffi.metatype("struct test_packet_t", {
	__index = {
		getLength = function() return 0 end,
		getData = function() return nil end,
	}
})

function Packet.new(proto, tbl, error)
	local self = {
		proto = proto,
		fillTbl = {}, depvars = {},
		dynvars = Dynvars.new()
	}

	for i,v in pairs(tbl) do
		local pkt, var = string.match(i, "^([%l%d]+)(%u.*)$");

		if pkt then
			if type(v) == "function" then
				self.fillTbl[i] = self.dynvars:add(pkt, var, v).value
			elseif type(v) == "table" then
				local ft = error:assert(v[1] and dependencies[v[1]],
					"Invalid table passed to field '%s'.", i)
				self.depvars[i] = { dep = ft, tbl = v }
				self.fillTbl[i] = true -- to overwrite on inherit
			else
				self.fillTbl[i] = v
			end
		else
			error("Invalid packet field %q. Format is 'layerField' (e.g. ip4Dst).", i)
		end
	end

	self.getPacket = packet["get" .. proto .. "Packet"]
	local pkt = self.getPacket(test_packet())
	self.minSize = ffi.sizeof(pkt:getName())
	self.hasPayload = pcall(function() type(pkt.payload) end)

	return setmetatable(self, Packet)
end

local function _inherit_depvars(self, other)
	for i,v in pairs(other.depvars) do
		if not self.depvars[i] and not self.fillTbl[i] then
			self.depvars[i] = v
		end
	end
end

function Packet:inherit(other)
	if other then
		self.dynvars:inherit(other.dynvars, self.fillTbl)
		_inherit_depvars(self, other)

		for i,v in pairs(other.fillTbl) do
			if not self.fillTbl[i] then
				self.fillTbl[i] = v
			end
		end
	end

	return self
end

function Packet:prepare(error, flow, final)
	if error:assertInvalidate(type(self.fillTbl.pktLength) == "number",
		"Packet field pktLength has to be set to a valid number.") then
		error:assertInvalidate(self.fillTbl.pktLength >= self.minSize,
			"Packet length is too short. Minimum size for %s is %d",
			self.proto, self.minSize)
	end

	if final then
		for i,v in pairs(self.depvars) do
			self.fillTbl[i] = v.dep.getValue(flow, v.tbl)
		end
	end

	self.dynvars:finalize()
end

return Packet
