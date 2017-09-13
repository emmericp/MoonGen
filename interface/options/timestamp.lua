local option = {}

option.description = "Start a second timestamped version of this flow."
option.configHelp = "Will also accept boolean values."


local translations = {
	["0"] = false, ["1"] = true,
	["false"] = false, ["true"] = true,
	["no"] = false, ["yes"] = true,
}

local translations_list = {}
for v in pairs(translations) do
	table.insert(translations_list, v)
end

function option.getHelp()
	return {
		{ string.format("(%s)", table.concat(translations_list, "|")), "Default use case."},
		{ nil, "Set option to true."},
	}
end

function option.parse(self, bool, error)
	if not bool then return end

	local t = type(bool)
	if t == "string" then
		bool = error:assert(translations[bool], "Invalid value. Can be one of %s.",
			table.concat(translations_list, ","))
	elseif t ~= "boolean" then
		error("Invalid argument. String or boolean expected, got %s.", t)
	end


	if bool and not error:assert(#self.rx == 1,
		"Cannot timestamp flows with more than one receiving device.") then
		return false
	end
	return bool
end

return option
