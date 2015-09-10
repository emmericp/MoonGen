require "utils"

local log = {}

-- terminates by calling error()
log.FATAL = 4
-- most likely terminates
log.ERROR = 3
-- something unexpected but not critical
log.WARN = 2
-- information for user
log.INFO = 1
-- debugging
log.DEBUG = 0

-- current log level
log.level = log.INFO

function log:setLevel(level)
	local prevLevel = self.level
	self.level = self[level] or self.INFO
	if not prevLevel == self.level then
		self:info("Changed log level to %s.", self[level] and level  or "INFO")
	end
end

-- file logging
log.fileEnabled = false
log.file = "log/debug.log"
log.fileLevel = log.DEBUG

function log:setFileLevel(level)
	self.fileLevel = self.level or self.DEBUG	
end

function log:fileEnable()
	self.fileEnabled = true
end

function log:fileDisable()
	self.fileEnabled = false
end

function log:writeToLog(str)
	local f = assert(io.open(self.file, "a"))
	f:write(getTimeMicros() .. " "  .. str .. "\n")
	f:close()
end

-- log functions
function log:fatal(str, ...)
	str = str:format(...)
		
	if self.fileEnabled then
		self:writeToLog("[FATAL] " .. str)
	end
	
	error(red(str), 2)
end

function log:error(str, ...)
	str = "[ERROR] " .. str:format(...)
		
	if self.ERROR >= self.level then
		print(bred(str))
	end	

	if self.fileEnabled and self.ERROR >= self.fileLevel then
		self:writeToLog(str)
	end
end

function log:warn(str, ...)
	str = "[WARN]  " .. str:format(...)
		
	if self.WARN >= self.level then
		print(yellow(str))
	end	

	if self.fileEnabled and self.WARN >= self.fileLevel then
		self:writeToLog(str)
	end
end

function log:info(str, ...)
	str = "[INFO]  " .. str:format(...)
		
	if self.INFO >= self.level then
		print(white(str))
	end	

	if self.fileEnabled and self.INFO >= self.fileLevel then
		self:writeToLog(str)
	end
end

function log:debug(str, ...)
	str = "[DEBUG] " .. str:format(...)
		
	if self.DEBUG >= self.level then
		print(str)
	end	

	if self.fileEnabled and self.DEBUG >= self.fileLevel then
		self:writeToLog(str)
	end
end

return log
