---------------------------------
--- @file main.lua
--- @brief Main ...
--- @todo TODO docu
---------------------------------

-- set up logger before doing anything else
local log 		= require "log"
-- set log level
log:setLevel("INFO")
-- enable logging to file
--log:fileEnable()

-- globally available utility functions
require "utils"
-- all available headers, packets, ... and their utility functions
require "proto.proto"

local dpdk		= require "dpdk"
local dpdkc		= require "dpdkc"
local dev		= require "device"
local stp		= require "StackTracePlus"
local ffi		= require "ffi"
local memory	= require "memory"
local serpent	= require "Serpent"

-- TODO: add command line switches for this and other luajit-debugging features
--require("jit.v").on()

local function getStackTrace(err)
	print(red("[FATAL] Lua error in task %s", MOONGEN_TASK_NAME))
	print(stp.stacktrace(err, 2))
end

local function run(file, ...)
	local script, err = loadfile(file)
	if not script then
		error(err)
	end
	xpcall(script, getStackTrace, ...)
end

local function getDpdkCfg(...)
       local args = { ... }
       for i, v in ipairs(args) do
               result, count = string.gsub(v, "%-%-dpdk%-config%=", "")
               if (count == 1) then
                       return i, result
               end
       end
       return nil, nil
end

local function parseCommandLineArgs(...)
	local args = { ... }

	local cfgindex, _ = getDpdkCfg(...)
	if cfgindex then
		table.remove(args, cfgindex)
	end

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

local function checkOS()
	local name, major, minor = getOS()
	if name ~= "Linux" then
		return log:warn("Could not detect Linux version")
	end
	if major >= 4 or major == 3 and minor > 13 then
		log:warn("You are running Linux >= 3.14, DDIO might not be working with DPDK in this setup!")
		log:warn("This can cause a huge performance impact (one memory access per packet!) preventing MoonGen from reaching line rate.")
		log:warn("Try using an older kernel (we recommend 3.13) if you see a low performance or huge cache miss ratio.")
	end
end

local function master(_, file, ...)
	log:info("Initializing DPDK. This will take a few seconds...")
	MOONGEN_TASK_NAME = "master"
	local _, cfgfile = getDpdkCfg(...)
	if not dpdk.init(cfgfile) then
		log:error("Could not initialize DPDK")
		return
	end
	local devices = dev.getDevices()
	log:info("Found %d usable devices:", #devices)
	for _, device in ipairs(devices) do
		printf("   Device %d: %s (%s)", device.id, device.mac, device.name)
	end
	checkOS()
	dpdk.userScript = file -- needs to be passed to slave cores
	local args = parseCommandLineArgs(...)
	arg = args -- for cliargs in busted
	run(file) -- should define a global called "master"
	xpcall(_G["master"], getStackTrace, unpack(args))
	-- exit program once the master task finishes
	-- it is up to the user program to wait for slaves to finish, e.g. by calling dpdk.waitForSlaves()
end

local function slave(taskId, userscript, args)
	-- must be done before parsing the args as they might rely on deserializers defined in the script
	run(userscript)
	args = loadstring(args)()
	func = args[1]
	if func == "master" then
		log:warn("Calling master as slave. This is probably a bug.")
	end
	if not _G[func] then
		log:fatal("slave function %s not found", func)
	end
	--require("jit.p").start("l")
	--require("jit.dump").on()
	MOONGEN_TASK_NAME = func
	MOONGEN_TASK_ID = taskId
	-- decode args
	local results = { select(2, xpcall(_G[func], getStackTrace, select(2, unpackAll(args)))) }
	local vals = serpent.dump(results)
	local buf = ffi.new("char[?]", #vals + 1)
	ffi.copy(buf, vals)
	dpdkc.store_result(taskId, buf)
	local ok, err = pcall(dev.reclaimTxBuffers)
	if ok then
		memory.freeMemPools()
	else
		log:warn("Could not reclaim tx memory: %s", err)
	end
	--require("jit.p").stop()
end

function main(task, ...)
	(task == "master" and master or slave)(...)
end

