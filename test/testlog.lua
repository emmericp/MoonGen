local testlog = {}

local log = require "log"

function testlog:info(input,...)
	input = input:format(...)
	local file = io.open("testlog.txt", "a")
	log:info(input)
	file:write("\n\\33[1;37m[INFO] " .. input)
end

function testlog:warn(input,...)
	input = input:format(...)
	local file = io.open("testlog.txt", "a")
	log:warn(input)
	file:write("\n\\33[1;33m[WARN] " .. input)
end

return testlog
