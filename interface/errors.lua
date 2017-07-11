local log = require "log"

local errors = {}

function errors:print(format, level, gLevel)
	format = format or "%s:%d: %s"
	level = level or "warn"
	gLevel = gLevel or "error"

	local cnt = #self
	if cnt == 0 then return end

	log[gLevel](log, "%d errors found while crawling config:", cnt)

	for _,v in ipairs(self) do
		log[level](log, format,
			v.info.short_src, v.info.currentline, v.msg
		)
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

	local info = debug.getinfo(level, "Sl")
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
