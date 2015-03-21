-- globally available utility functions
require "utils"
require "packet"

local dpdk		= require "dpdk"
local dpdkc		= require "dpdkc"
local dev		= require "device"
local stp		= require "StackTracePlus"
local ffi		= require "ffi"
local serpent	= require "Serpent"

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
		-- currently not supported as we can't pass structs to slaves
		-- ip?
		-- local ip = parseIPAddress(v)
		-- if ip then
		-- 	v = ip
		-- end
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

local function slave(taskId, args)
	args = loadstring(args)()
	file, func = unpack(args)
	if func == "master" then
		print("[WARNING] Calling master as slave. This is probably a bug.")
	end
	--require("jit.p").start("l")
	--require("jit.dump").on()
	MOONGEN_TASK_NAME = func
	MOONGEN_TASK_ID = taskId
	run(file)
	-- decode args
	local results = { select(2, xpcall(_G[func], getStackTrace, select(3, unpackAll(args)))) }
	local vals = serpent.dump(results)
	local buf = ffi.new("char[?]", #vals + 1)
	ffi.copy(buf, vals)
	dpdkc.store_result(taskId, buf)
	--require("jit.p").stop()
end

function main(task, ...)
	(task == "master" and master or slave)(...)
end

