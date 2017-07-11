local log = require "log"

local errors = {}

function errors:print()
	local cnt = #self
	if cnt == 0 then return end

	log:error("%d errors found while crawling config:", cnt)

	for _,v in ipairs(self) do
		if v.info then
			log:warn("%s:%d: %s", v.info.short_src, v.info.currentline, v.msg)
		else
			log:warn(v.msg)
		end
	end
end

function errors:log(level, message, ...)
	if type(level) == "string" then
		message = string.format(level, message, ...)
		level = 4
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

function errors:assert(test, ...)
	if not test then
		errors.log(self, ...)
	end
end

return function()
	return setmetatable({}, {
		__index = errors,
		__call = errors.log
	})
end
