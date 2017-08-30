local flow
local function _update_delay_one()
	flow.updatePacket = flow._update_packet
	flow._update_packet = nil
end

-- closures are ok because the script is reinstanced per slave-thread
local _single_index, _alt_index = 0, 0
local _valid_modes = {
	none = true, -- setting this makes validation easier (see option.test)
	single = function(dv, pkt)
		dv[_single_index + 1]:update()
		dv:applyAll(pkt)
		_single_index = incAndWrap(_single_index, dv.count) -- luacheck: globals incAndWrap
	end,
	alternating = function(dv, pkt)
		dv[_alt_index + 1]:updateApply(pkt)
		_alt_index = incAndWrap(_alt_index, dv.count) -- luacheck: globals incAndWrap
	end,
	random = function(dv, pkt)
		local index = math.random(dv.count)
		dv[index]:update()
		dv:applyAll(pkt)
	end,
	random_alt = function(dv, pkt)
		local index = math.random(dv.count)
		dv[index]:updateApply(pkt)
	end,
	all = function(dv, pkt)
		dv:updateApplyAll(pkt)
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
	flow = self
	self.updatePacket = _update_delay_one

	local t = type(mode)
	if t ~= "function" then
		mode = t == "string" and _valid_modes[string.lower(mode)]
	end

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
	elseif t ~= "function" then
		error(4, "Option 'mode': Invalid argument. String expected, got %s.", t)
		return false
	end

	return true
end

return option
