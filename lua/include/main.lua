-- globally available utility functions
require "utils"
require "packet"

local dpdk	= require "dpdk"
local dev	= require "device"
local stp	= require "StackTracePlus"

-- TODO: add command line switches for this and other luajit-debugging features
--require("jit.v").on()

local function getStackTrace(err)
	printf("[ERROR] Lua error in task %s", MOONGEN_TASK_NAME)
	print(stp.stacktrace(err, 2))
end

local function run(file, ...)
	local script, err = loadfile(file)
	if not script then
		error(err)
	end
	xpcall(script, getStackTrace, ...)
end

local function parseCommandLineArgs(...)
	local args = { ... }
	for i, v in ipairs(args) do
		-- is it just a simple number?
		if tonumber(v) then
			v = tonumber(v)
		end
		-- ip?
		local ip = parseIPAddress(v)
		if ip then
			v = ip
		end
		args[i] = v
	end
	return args
end

local function master(_, file, ...)
	MOONGEN_TASK_NAME = "master"
	if not dpdk.init() then
		print("Could not initialize DPDK")
		return
	end
	local devices = dev.getDevices()
	printf("Found %d usable ports:", #devices)
	for _, device in ipairs(devices) do
		printf("   Ports %d: %s (%s)", device.id, device.mac, device.name)
	end
	dpdk.userScript = file -- needs to be passed to slave cores
	local args = parseCommandLineArgs(...)
	arg = args -- for cliargs in busted
	run(file) -- should define a global called "master"
	xpcall(_G["master"], getStackTrace, unpack(args))
	-- exit program once the master task finishes
	-- it is up to the user program to wait for slaves to finish, e.g. by calling dpdk.waitForSlaves()
end

local function slave(file, func, ...)
	--require("jit.p").start("l")
	--require("jit.dump").on()
	MOONGEN_TASK_NAME = func
	run(file)
	-- decode args
	local args = { ... }
	-- TODO: ugly work-around until someone implements proper serialization
	for i, v in ipairs(args) do
		if type(v) == "table" then
			local obj = {}
			for v in v[1]:gmatch("([^,]+)") do
				obj[#obj + 1] = v
			end
			if obj[1] == "device" then
				args[i] = dev.get(tonumber(obj[2]))
			elseif obj[1] == "rxQueue" then
				args[i] = dev.get(tonumber(obj[2])):getRxQueue(tonumber(obj[3]))
			elseif obj[1] == "txQueue" then
				args[i] = dev.get(tonumber(obj[2])):getTxQueue(tonumber(obj[3]))
			end
		end
	end
	xpcall(_G[func], getStackTrace, unpack(args))
	--require("jit.p").stop()
end

function main(task, ...)
	(task == "master" and master or slave)(...)
end

