-- setup package paths
package.path = package.path .. ";include/?.lua;/include/?/init.lua;include/lib/?/init.lua"

-- globally available utility functions
require "utils"

local dpdk	= require "dpdk"
local dev	= require "device"
local stp	= require "StackTracePlus"

-- disable gc
collectgarbage("stop")

-- TODO: add command line switches for this and other luajit-debugging features
--require("jit.v").on()

local function getStackTrace(err)
	printf("[ERROR] Lua error in task %s", MOONGEN_TASK_NAME)
	print(stp.stacktrace(err, 2))
end

local function run(file)
	local script, err = loadfile(file)
	if not script then
		error(err)
	end
	xpcall(script, getStackTrace)
end

local function master(_, file, ...)
	MOONGEN_TASK_NAME = "master"
	dpdk.init()
	dev.init()
	local devices = dev.getDevices()
	printf("Found %d usable ports:", #devices)
	for _, device in ipairs(devices) do
		printf("   Ports %d: %s (%s)", device.id, device.mac, device.name)
	end
	dpdk.userScript = file -- needs to be passed to slave cores
	run(file) -- should define a global called "master"
	xpcall(_G["master"], getStackTrace, ...)
	-- exit program once the master task finishes
	-- it is up to the user program to wait for slaves to finish, e.g. by calling dpdk.waitForSlaves()
	os.exit(0)
end

local function slave(file, func, ...)
	MOONGEN_TASK_NAME = func
	run(file)
	xpcall(_G[func], getStackTrace, ...)
end


(... == "master" and master or slave)(select(2, ...))

