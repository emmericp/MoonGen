-- Testlog.lua library

-- Overrides needed functions of lua/log to extend their functionality to:
-- - Additionally write all output to a temporary log file

local testlog = {}

local log = require "log"

-- Extend log:info(input,...)
function testlog:info(input,...)
	input = input:format(...)
	local file = io.open("/tmp/testlog.txt", "a")
	log:info(input)
	file:write("\\33[1;37m[INFO] " .. input .. "\n")
	file:close()
end

-- Extend log:warn(input,...)
function testlog:warn(input,...)
	input = input:format(...)
	local file = io.open("/tmp/testlog.txt", "a")
	log:warn(input)
	file:write("\\33[1;33m[WARN] " .. input .. "\n")
	file:close()
end

-- Return library
return testlog