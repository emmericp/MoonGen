local errors = {}

function errors:print(fn, ...)
	for _,v in ipairs(self) do
		if v.info then
			v.msg = string.format("%s:%d: %s", v.info.short_src, v.info.currentline, v.msg)
		end

		fn(..., v.msg)
	end
end

function errors:log(level, message, ...)
	if type(level) == "string" then
		message = string.format(level, message, ...)
		level = 3
	else
		message = string.format(message, ...)
		level = level + 1
	end

	local info
	if level > 1 then
		info = debug.getinfo(level, "Sl")
	end

	table.insert(self, {
		info = info, msg = message
	})
end

function errors:assert(test, level, ...)
	if not test then
		if type(level) == "number" then
			errors.log(self, level + 1, ...)
		else
			error.log(self, 3, level, ...)
		end
	end
end

function errors:count()
	return #self
end

return function()
	return setmetatable({}, {
		__index = errors,
		__call = errors.log
	})
end
