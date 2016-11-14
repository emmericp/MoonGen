--- MoonGen pre-1.0 compatibility layer

local log     = require "log"
local dpdk    = require "dpdk"
local moongen = require "moongen"
local device  = require "device"

dpdk.__name = "dpdk"
moongen.__name = "moongen"

-- make functions that were moved to the libmoons/moongen module available
local function deprecatedFunction(oldMod, oldName, newMod, newName)
	newName = newName or oldName
	oldMod[oldName] = function(...)
		if not oldMod.__deprecatedWarnings then
			oldMod.__deprecatedWarnings = {}
		end
		if not oldMod.__deprecatedWarnings[oldName] then
			log:warn("%s.%s() is deprecated, use %s.%s() instead.", oldMod.__name, oldName, newMod.__name, newName)
			oldMod.__deprecatedWarnings[oldName] = true
		end
		return newMod[newName](...)
	end
end

deprecatedFunction(dpdk, "launchLua", moongen, "startTask")
deprecatedFunction(dpdk, "launchLuaOnCore", moongen, "startTaskOnCore")
deprecatedFunction(dpdk, "waitForSlaves", moongen, "waitForTasks")
deprecatedFunction(dpdk, "getCores", moongen)
deprecatedFunction(dpdk, "getCycles", moongen)
deprecatedFunction(dpdk, "getCyclesFrequency", moongen)
deprecatedFunction(dpdk, "getTime", moongen)
deprecatedFunction(dpdk, "setRuntime", moongen)
deprecatedFunction(dpdk, "running", moongen)
deprecatedFunction(dpdk, "stop", moongen)
deprecatedFunction(dpdk, "sleepMillis", moongen)
deprecatedFunction(dpdk, "sleepMicros", moongen)
deprecatedFunction(dpdk, "sleepMillisIdle", moongen)
deprecatedFunction(dpdk, "sleepMicrosIdle", moongen)
deprecatedFunction(dpdk, "getCore", moongen)
deprecatedFunction(dpdk, "disableBadSocketWarning", moongen)


local oldConfig = device.config

function device.config(...)
	if type((...)) == "number" then
		local args = {...}
	    -- this is for legacy compatibility when calling the function  without named arguments
		log:warn("device.config() without named arguments is deprecated and will be removed. See documentation for libmoons device.config().")
		if not args[2] or type(args[2]) == "number" then
			args.port       = args[1]
			args.rxQueues   = args[2]
			args.txQueues   = args[3]
			args.rxDescs    = args[4]
			args.txDescs    = args[5]
			args.speed      = args[6]
			args.dropEnable = args[7]
		else -- called with mempool which was changed to mempools (one per queue)
			log:fatal("mempool option was removed. See libmoon device.config() for the new \"mempools\" option.")
		end
		return oldConfig(args)
	end
	local args = ...
	if args.rssNQueues then
		log:warn("rssNQueues has been renamed to rssQueues, udate your script.")
		args.rssQueues = args.rssNQueues
	end
	return oldConfig(...)
end


