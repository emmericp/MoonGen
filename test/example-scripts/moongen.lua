local mg = {}

local proc = {}
proc.__index = proc

function mg.start(script, ...)
	local str = ""
	for i = 1, select("#", ...) do
		-- TODO: escape arguments properly
		str = str .. " \"" .. select(i, ...) .. "\""
	end
	local obj = setmetatable({}, proc)
	obj.proc = io.popen("cd ../.. && ./build/MoonGen " .. script .. str)
	return obj
end

local function appendArg(a, ...)
	local varArgs = { ... }
	varArgs[#varArgs + 1] = a
	return unpack(varArgs)
end

function proc:waitFor(expr1, expr2)
	local lines = {}
	for line in self.proc:lines() do
		print("[Output] " .. line)
		lines[#lines + 1] = line
		if line:match(expr1) then
			return appendArg(lines, appendArg(1, appendArg(line, line:match(expr1))))
		elseif expr2 and line:match(expr2) then
			return appendArg(lines, appendArg(2, appendArg(line, line:match(expr2))))
		end
	end
	return false, lines
end

function proc:waitForPorts(numPorts, expectedSpeed)
	expectedSpeed = expectedSpeed or 10
	local found = 0
	while true do
		local state, speed, line = self:waitFor("Port %d+ %S+ is (%S+): %S+ (%d+) MBit", "(%d+) ports are up(%.)$")
		if line:match("ports are up") then
			assert(numPorts == found, ("expected %s ports, found %s"):format(numPorts, found))
			return true
		end
		found = found + 1
		assert(state and speed)
		if state ~= "up" then
			print("Port down: " .. line)
			assert(false)
		end
		speed = tonumber(speed) / 1000
		if speed ~= expectedSpeed then
			print("Wrong link speed: " .. line)
			assert(false)
		end
	end
end

function proc:kill(signal)
	signal = signal or "TERM"
	-- TODO: get the correct pid instead of killall :>
	os.execute("killall -" .. signal .. " MoonGen")
end

function proc:running()
	local pidProc = io.popen("pidof sshda")
	local pid = pidProc:read()
	pidProc:close()
	return not not pid
end

function proc:destroy()
	self:kill()
	if self:running() then
		os.execute("sleep 1")
		self:kill("KILL")
	end
	self.proc:close()
end

return mg
