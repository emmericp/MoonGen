local option = {}

option.description = "Overwrite uid used for this flow. Useful to receive flows"
	.. " sent by another instance."
option.configHelp = "Will also accept number values. Same restrictions as explained above."
option.usage = {
	{ "<number>", "Set the uid of this flow to <number>. Needs to be a unique integer greater than zero."},
}

local uids = {}

local function next_uid() -- simulating pure lua # operator + 1
	local i = 1
	while uids[i] do i = i + 1 end
	return i
end

function option.parse(flow, number, error)
	if flow:property "uid" then return flow:property "uid" end

	local t = type(number)
	if type(number) == "string" then
		number = error:assert(tonumber(number), "Invalid string. Needs to be convertible to a number.")
	elseif t ~= "number" and t ~= "nil" then
		error("Invalid argument. String or number expected, got %s.", t)
		number = nil
	end

	if not number or not assert(number > 0 and not uids[number],
		"Invalid value. Needs to be a unique positive integer.") then
		number = next_uid()
	end

	uids[number] = true
	flow:setProperty("uid", number)
	return number
end

return option
