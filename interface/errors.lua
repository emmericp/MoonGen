local errors = {}

function errors:print(info, fn, ...)
	for _,v in ipairs(self) do
		if info and v.info then
			fn(..., string.format("%s:%d: %s", v.info.short_src, v.info.currentline, v.msg))
		else
			fn(..., v.msg)
		end
	end
end

function errors:setPrefix(pre, ...)
	if pre then
		self.prefix = string.format(pre, ...)
	else
		self.prefix = nil
	end
end

function errors:log(level, message, ...)
	if type(level) == "string" then
		message = string.format(level, message, ...)
		level = self.defaultLevel
	else
		message = string.format(message, ...)
		level = level + 1
	end

	if self.prefix then
		message = self.prefix .. message
	end

	local info
	if level > 1 then
		info = debug.getinfo(level, "Sl")
	end

	table.insert(self, {
		info = info, msg = message
	})
end

function errors:logInvalidate(...)
	self.valid = false
	errors.log(self, ...)
end

local function _assert(self, logfn, test, level, ...)
	if not test then
		if type(level) == "number" then
			level = (level > 0) and level + 1 or level
			errors[logfn](self, level, ...)
		else
			errors[logfn](self, self.defaultLevel, level, ...)
		end
	end
	return test
end

function errors:assert(...)
	return _assert(self, "log", ...)
end

function errors:assertInvalidate(...)
	return _assert(self, "logInvalidate", ...)
end

function errors:count()
	return #self
end

return function()
	return setmetatable({ valid = true, defaultLevel = 3 }, {
		__index = errors,
		__call = errors.log
	})
end
