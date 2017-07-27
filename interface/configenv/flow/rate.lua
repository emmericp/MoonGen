local _time_units = {
	[""] = 1, ms = 1 / 1000, s = 1, m = 60, h = 3600
}

local _size_units = {
	[""] = 1,
	k = 10 ^ 3, ki = 2 ^ 10,
	m = 10 ^ 6, mi = 2 ^ 20,
	g = 10 ^ 9, gi = 2 ^ 30
}

local function _parse_rate(rstring, psize)
	local num, unit, time = string.match(rstring, "^(%d+%.?%d*)(%a*)/?(%a*)$")
	if not num then
		return nil, "Invalid format. Should be '<number>[unit][/<time>]'."
	end

	num, unit, time = tonumber(num), string.lower(unit), _time_units[time]
	if not time then
		return nil, "Invalid time unit. Can be one of 'ms', 's', 'm', 'h'."
	end

	if unit == "" then
		unit = _size_units.m * 8
	elseif string.find(unit, "bit$") then
		unit = _size_units[string.sub(unit, 1, -4)]
	elseif string.find(unit, "b$") then
		unit = _size_units[string.sub(unit, 1, -2)] * 8
	elseif string.find(unit, "p$") then
		unit = _size_units[string.sub(unit, 1, -2)] * psize
	else
		return nil, "Invalid size unit. Can be <k|m|g>[i]<bit|b|p>"
	end

	unit = unit / 10 ^ 6 -- cbr is in mbit/s
	return num * unit / time
end


local option = {}

function option.parse(self, rate)
  if type(rate) == "number" then
    self.cbr = rate
  elseif type(rate) == "string" then
    self.cbr = _parse_rate(rate, self.packet:size())
  end
end

function option.test(error, rate)
  local t = type(rate)
  if t == "string" then
    local status, msg = _parse_rate(rate, 1)
    error:assert(status, 4, "Option 'rate': %s", msg)
  elseif t ~= "number" then
    error(4, "Option 'rate': Invalid argument, string or number expected, got %s.", t)
  end
end

return option
