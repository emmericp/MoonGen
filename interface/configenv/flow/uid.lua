local option = {}

option.description = "Overwrite uid used for this flow. Useful to receive flows"
	.. " sent by another instance."
option.configHelp = "Will also accept number values. Same restrictions as explained above."

function option.getHelp()
	return {
		{ "<number>", "Set the uid of this flow to <number>. Needs to be a unique integer greater than zero."},
	}
end

function option.parse(_, number, error)
	if not number then return end

	local t = type(number)
	if type(number) == "string" then
		number = error:assert(tonumber(number), "Invalid string. Needs to be convertible to a number.")
	elseif t ~= "number" then
		error("Invalid argument. String or number expected, got %s.", t)
		number = nil
	end

	if number and assert(number > 0, "Invalid value. Needs to be a unique positive integer.") then
		return number
	end
end

return option
