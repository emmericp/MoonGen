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

function option.parse(self, bool)
	if type(bool) == "boolean" then
		self.ts = bool
	elseif type(bool) == "string" then
		self.ts = translations[bool]
	end
end

function option.validate() end

function option.test(_, error, bool)
	local t = type(bool)

	if t == "string" then
    local result = type(translations[bool]) ~= "nil"
    error:assert(result, "Option 'timestamp': Invalid value. Can be one of %s.", table.concat(translations_list, ","))
    return result
	elseif t ~= "boolean" and t ~= "nil" then
		error(4, "Option 'timestamp': Invalid argument. String or boolean expected, got %s.", t)
		return false
	end

	return true
end

return option
