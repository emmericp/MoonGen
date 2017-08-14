local function _update_delay_one(self)
	self.updatePacket = self._update_packet
	self._update_packet = nil
end

-- TODO add modes that apply all instead of apply single
local _valid_modes = {
	none = true, -- setting this makes validation easier (see option.test)
	single = function(self, pkt)
		local index = self._update_index or 0
		self.packet.dynvars[index + 1]:updateApply(pkt)
		self._update_index = incAndWrap(index, #self.packet.dynvars) -- luacheck: globals incAndWrap
	end,
	random = function(self, pkt)
		local index = math.random(self.packet.dynvars.count)
		self.packet.dynvars[index]:updateApply(pkt)
	end,
	all = function(self, pkt)
		self.packet.dynvars:updateApplyAll(pkt)
	end,
}

local _modelist = {}
for i in pairs(_valid_modes) do
	table.insert(_modelist, i)
end

local option = {}

option.formatString = {}
for _,v in ipairs(_modelist) do
	table.insert(option.formatString, v)
end
option.formatString = "<" .. table.concat(option.formatString, "|") .. ">"
option.helpString = "Change how dynamic fields are updated. (default = single)"
-- TODO add value documentation

function option.parse(self, mode)
	if #self.packet.dynvars == 0  or mode == "none" then
		return -- packets will not change
	end

	-- Don't change the first packet
	self.updatePacket = _update_delay_one

	mode = type(mode) == "string" and _valid_modes[string.lower(mode)]
	self._update_packet = mode or _valid_modes.single
end

function option.validate() end

function option.test(self, error, mode)
	local t = type(mode)
	if t == "string" then
		error:assert(#self.packet.dynvars > 0, 4, "Option 'mode': Value set, but no dynvars in associated packet.")

		if not _valid_modes[string.lower(mode)] then
			error(4, "Option 'mode': Invalid value %q. Can be one of %s.",
				mode, table.concat(_modelist, ", "))
			return false
		end
	else
		error(4, "Option 'mode': Invalid argument. String expected, got %s.", t)
		return false
	end

	return true
end

return option
