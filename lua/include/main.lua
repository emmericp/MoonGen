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

local function master(_, file, ...)
	MOONGEN_TASK_NAME = "master"
	dpdk.init()
	local devices = dev.getDevices()
	printf("Found %d usable ports:", #devices)
	for _, device in ipairs(devices) do
		printf("   Ports %d: %s (%s)", device.id, device.mac, device.name)
	end
	dpdk.userScript = file -- needs to be passed to slave cores
	arg = {...} -- for cliargs in busted
	run(file) -- should define a global called "master"
	xpcall(_G["master"], getStackTrace, ...)
	-- exit program once the master task finishes
	-- it is up to the user program to wait for slaves to finish, e.g. by calling dpdk.waitForSlaves()
end

local function slave(file, func, ...)
	package.path = package.path .. ";../luajit/src/?.lua"
	--require("jit.p").start("l")
	MOONGEN_TASK_NAME = func
	run(file)
	xpcall(_G[func], getStackTrace, ...)
	--require("jit.p").stop()
end

function main(task, ...)
	(task == "master" and master or slave)(...)
end

