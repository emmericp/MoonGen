local validator = {}

function validator.new()
	return setmetatable({ valid = true }, {
		__index = validator,
		__call = validator.report
	})
end

function validator:report(...)
	self.valid = false
	table.insert(self, string.format(...))
end

function validator:assert(test, ...)
	if not test then
		self:report(...)
	end
end

function validator:print(fn, ...)
	for _,v in ipairs(self) do
		fn(..., v)
	end
end

return setmetatable(validator, { __call = function() return validator.new() end})
