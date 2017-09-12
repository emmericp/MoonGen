local option = {}

option.description = "Overwrite uid used for this flow. Useful to receive flows"
	.. " sent by another instance."
option.configHelp = "Will also accept number values. Same restrictions as explained above."

function option.getHelp()
	return {
		{ "<number>", "Set the uid of this flow to <number>. Needs to be a unique integer greater than zero."},
	}
end

function option.parse(self, number)
	if type(number) == "number" then
		self.uid = number
	elseif type(number) == "string" then
		self.uid = tonumber(number)
	end
end

function option.validate() end

function option.test(_, error, number)
	local t = type(number)

	if t == "string" then
		number = tonumber(number)
		if not number or number <= 0  then
			error("Option 'uid': Invalid value. Needs to be a unique positive integer.")
			return false
		end
	elseif t ~= "number" and t ~= "nil" then
		error(4, "Option 'uid': Invalid argument. String or number expected, got %s.", t)
		return false
	elseif number <= 0 then
		error("Option 'uid': Invalid value. Needs to be a unique positive integer.")
		return false
	end

	return true
end

return option
