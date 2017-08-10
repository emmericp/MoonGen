local units = require "configenv.flow.units"

local option = {}

local function _parse_limit(lstring, psize)
	local num, unit = string.match(lstring, "^(%d+%.?%d*)(%a+)$")
	if not num then
		return nil, "Invalid format. Should be '<number><unit>'."
	end

	num, unit = tonumber(num), string.lower(unit)
	if unit == "" then
		unit = units.size.m --default is mbit
	elseif string.find(unit, "bit$") then
		unit = units.size[string.sub(unit, 1, -4)]
	elseif string.find(unit, "b$") then
		unit = units.size[string.sub(unit, 1, -2)] * 8
	elseif string.find(unit, "p$") then
		unit = units.size[string.sub(unit, 1, -2)] * psize * 8
	else
		return nil, unit.sizeError
	end

	return num * unit / (psize * 8)
end

-- TODO round up or down?
function option.parse(self, limit)
	local psize = self:getPacketLength(true)
	if type(limit) == "number" then
		self.dlim = limit * units.size.m / (psize * 8)
	elseif type(limit) == "string" then
		self.dlim = _parse_limit(limit, psize)
	end
end

function option.validate() end

function option.test(_, error, limit)
	local t = type(limit)

	if t == "string" then
		local status, msg = _parse_limit(limit, 1)
		error:assert(status, 4, "Option 'dataLimit': %s", msg)
		return type(status) ~= "nil"
	elseif t ~= "number" and t ~= "nil" then
		error(4, "Option 'dataLimit': Invalid argument. String or number expected, got %s.", t)
		return false
	end

	return true
end

return option
