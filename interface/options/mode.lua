local function get_update_delay_one(flow)
	return function()
		flow.updatePacket = flow._update_packet
		flow._update_packet = nil
	end
end

local function _random(dv, pkt)
	local index = math.random(dv.count)
	dv[index]:update()
	dv:applyAll(pkt)
end

local function _random_alt(dv, pkt)
	local index = math.random(dv.count)
	dv[index]:updateApply(pkt)
end

local function _all(dv, pkt)
	dv:updateApplyAll(pkt)
end

local _valid_modes = {
	single = function()
		local index = 0
		return function(dv, pkt)
			dv[index + 1]:update()
			dv:applyAll(pkt)
			index = incAndWrap(index, dv.count) -- luacheck: globals incAndWrap
		end
	end,
	alternating = function()
		local index = 0
		return function(dv, pkt)
			dv[index + 1]:updateApply(pkt)
			index = incAndWrap(index, dv.count) -- luacheck: globals incAndWrap
		end
	end,
	random = function() return _random end,
	random_alt = function() return _random_alt end,
	all = function() return _all end,
}

local _modelist = { "none" }
for i in pairs(_valid_modes) do
	table.insert(_modelist, i)
end

local option = {}

option.description = "Control how fields of dynamic flows are updated and applied."
option.configHelp = "Will also accept a function that will be called for each"
	.. " packet sent but the first. Use closures for flow control purposes."
	.. " The following function demonstrates the available api:\n\n"
	.. [[function mode(dynvars, packet)
	-- available api
	dynvars[1]:update()
	dynvars[1]:apply(packet)
	dynvars[1]:updateApply(packet)

	-- convenience api
	dynvars:updateAll()
	dynvars:applyAll(packet)
	dynvars:updateApplyAll(packet)
end]]
	.. "\n\nSingle dynvars can also be accessed by name using"
	.. " 'dynvars.index.<pktVar>' (e.g. udpSrc)."
option.usage = {
	{ "none", "Ignore all dynamic fields and send the first packet created." },
	{ "single", "Update one field at a time, but apply every change so far." },
	{ "alternating", "Update and apply one field at a time." },
	{ "random", "Like single, but the order of updates is not fixed."},
	{ "random_alt", "Like alternating, but the order of updates is not fixed."},
	{ "all", "Update and apply all fields every time."},
}

option.formatString = {}
for _,v in ipairs(_modelist) do
	table.insert(option.formatString, v)
end
option.formatString = "<" .. table.concat(option.formatString, "|") .. ">"
option.helpString = "Change how dynamic fields are updated. (default = single)"

function option.parse(self, mode, error)
	if #self.packet.dynvars == 0 then
		error:assert(not mode or mode == "none",
			"Value set, but no dynvars in associated packet.")
		return
	elseif mode == "none" then
		return
	end

	-- Don't change the first packet
	self.updatePacket = get_update_delay_one(self)

	local t = type(mode)
	if t == "string" then
		mode = error:assert(_valid_modes[string.lower(mode)], "Invalid value %q. Can be one of %s.",
			mode, table.concat(_modelist, ", "))

		if mode then
			mode = mode()
		end
	elseif t ~= "function" and t ~= "nil" then
		error("Invalid argument. String or function expected, got %s.", t)
	end

	self._update_packet = mode or _valid_modes.single()
end

return option
