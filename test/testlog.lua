local testlog = {}

local log = require "log"

function testlog:info(input,...)
	input = input:format(...)
	local file = io.open("/tmp/testlog.txt", "a")
	log:info(input)
	file:write("\\33[1;37m[INFO] " .. input .. "\n")
	file:close()
end

function testlog:warn(input,...)
	input = input:format(...)
	local file = io.open("/tmp/testlog.txt", "a")
	log:warn(input)
	file:write("\\33[1;33m[WARN] " .. input .. "\n")
	file:close()
end

return testlog
