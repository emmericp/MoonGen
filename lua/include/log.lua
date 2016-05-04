---------------------------------
--- @file log.lua
--- @brief Logging module.
--- @todo Docu
---------------------------------
require "utils"

local log = {}

------------------------------------------------------
---- Log Levels
------------------------------------------------------

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


----------------------------------------------------
---- stdout Logging
----------------------------------------------------

-- current log level
log.level = log.INFO

--- Set the log level
--- @param level Set log level to level. Default: INFO
function log:setLevel(level)
	local prevLevel = self.level
	self.level = self[level] or self.INFO
	if not prevLevel == self.level then
		self:info("Changed log level to %s.", self[level] and level  or "INFO")
	end
end

----------------------------------------------------
---- File Logging
----------------------------------------------------

-- en- or disable file logging
log.fileEnabled = false

--- Enable logging to file
function log:fileEnable()
	self.fileEnabled = true
	self:info("Enabled logging to '" .. log.file .. "'")
end

--- Disable logging to file
function log:fileDisable()
	self.fileEnabled = false
	self:info("Disabled logging to " .. log.file .. "'")
end

-- current file log level 
log.fileLevel = log.DEBUG

--- Set the file log level.
--- @param level Set file log level to level. Default: DEBUG
function log:setFileLevel(level)
	self.fileLevel = self.level or self.DEBUG	
end

--- path to log file
log.file = nil

log.locations = {
	"log/",
	"../log/",
}

do
	local function fileExists(f)
		local file = io.open(f, "r")
		if file then
			file:close()
		end
		return not not file
	end
	-- find log/ path
	for _, f in ipairs(log.locations) do
		if fileExists(f) then
			log.file = f .. "debug.log"
		end
	end
	if not log.file then
		log.file = "debug.log"
		-- print("Unable to locate log directory. Logging to debug.log in working directory.")
	end
	-- print("Logging to " .. log.file)
end

--- Write a message to the log file specified in log.file
--- @param str Log message.
function log:writeToLog(str)
	local f = assert(io.open(self.file, "a"))
	f:write(getTimeMicros() .. " "  .. str .. "\n")
	f:close()
end


---------------------------------------------------
---- Logging Functions
---------------------------------------------------

--- Log a message, level FATAL.
--- This message is written with error(), hence, terminates the application.
--- FATAL log messages to stdout cannot be disabled.
--- @param str Log message
--- @param args Formatting parameters
function log:fatal(str, ...)
	str = str:format(...)
		
	if self.fileEnabled then
		self:writeToLog("[FATAL] " .. str)
	end
	
	error(red(str), 2)
end

--- Log a message, level ERROR.
--- @param str Log message
--- @param args Formatting parameters
function log:error(str, ...)
	str = "[ERROR] " .. str:format(...)
		
	if self.ERROR >= self.level then
		print(bred("%s", str))
	end	

	if self.fileEnabled and self.ERROR >= self.fileLevel then
		self:writeToLog(str)
	end
end

--- Log a message, level WARN.
--- @param str Log message
--- @param args Formatting parameters
function log:warn(str, ...)
	str = "[WARN]  " .. str:format(...)
		
	if self.WARN >= self.level then
		print(yellow("%s", str))
	end	

	if self.fileEnabled and self.WARN >= self.fileLevel then
		self:writeToLog(str)
	end
end

--- Log a message, level INFO.
--- @param str Log message
--- @param args Formatting parameters
function log:info(str, ...)
	str = "[INFO]  " .. str:format(...)
		
	if self.INFO >= self.level then
		print(white("%s", str))
	end	

	if self.fileEnabled and self.INFO >= self.fileLevel then
		self:writeToLog(str)
	end
end

--- Log a message, level DEBUG.
--- @param str Log message
--- @param args Formatting parameters
function log:debug(str, ...)
	str = "[DEBUG] " .. str:format(...)
		
	if self.DEBUG >= self.level then
		print(green("%s", str))
	end	

	if self.fileEnabled and self.DEBUG >= self.fileLevel then
		self:writeToLog(str)
	end
end

return log
