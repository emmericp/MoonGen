
-- compatibility stuff for deprecated functions
require "moongen-compat"

-- load moongen-specific modules
require "software-timestamps"
require "crc-ratecontrol"
require "software-ratecontrol"

-- set up logger before doing anything else
local log = require "log"
-- set log level
log:setLevel("INFO")
-- enable logging to file
--log:fileEnable()

-- globally available utility functions
require "utils"

local libmoon     = require "libmoon"
local dpdk       = require "dpdk"
local dpdkc      = require "dpdkc"
local device     = require "device"
local stp        = require "StackTracePlus"
local ffi        = require "ffi"
local memory     = require "memory"
local serpent    = require "Serpent"
local argparse   = require "argparse"
local mg         = require "moongen"

-- libmoon main, contains main()
require "main"
local libmoon_main = main

local function getStackTrace(err)
	print(red("[FATAL] Lua error in task %s", LIBMOON_TASK_NAME))
	print(stp.stacktrace(err, 2))
end

local function run(file, ...)
	local script, err = loadfile(file)
	if not script then
		error(err)
	end
	return xpcall(script, getStackTrace, ...)
end

local function dashdashSplitArgs(...)
    local args = { ... }
    local multiargs = {{}}
    local k = 1
    for i, arg in ipairs(args) do
		if arg == "--" then
			k = k + 1
			multiargs[k] = {}
        else
            table.insert(multiargs[k], arg)
        end
	end
    return multiargs
end

local function configure_common(parser, defaults0, defaults1)
	function convertTime(str)
		local pattern = "^(%d+)([mu]?s)$"
		local _, _, n, unit = string.find(str, pattern)
		if not (n and unit) then
			parser:error("failed to parse time '"..str.."', it should match '"..pattern.."' pattern")
		end
		return {n=tonumber(n), unit=unit}
	end

    local defaults = {}
    for _, k in ipairs{"rx_queues", "tx_queues"} do
        defaults[k] = defaults1[k] or defaults0[k]
    end

    parser:option("--buf", "RX/TX buffer size."):convert(tonumber)
    parser:option("--rx-buf", "RX buffer size, overrides --buf."):convert(tonumber)
    parser:option("--tx-buf", "TX buffer size, overrides --buf."):convert(tonumber)
	parser:option("--ipg", "Inter-packet gap, time units (s, ms, us) must be specified."):convert(convertTime)
    -- TODO: add delay option
    parser:option("--rx-queues", "Number of RX queues per task."):convert(tonumber):default(defaults.rx_queues)
    parser:option("--tx-queues", "Number of TX queues per task."):convert(tonumber):default(defaults.tx_queues)
end

local function configure_main(parser)
    parser:description("Task manager used to run any number of various tasks.")
	parser:epilog(string.format("Run multiple tasks: \n\t%s [tman options...] [-- <task1-file> [task1 options...]] [-- <task2-file> [task2 options...]] [-- ...]\nGet help on a certain task:\n\t%s -- <task-file> -h", parser._name, parser._name))
    parser:option("-d --dev", "Devices to transmit from/to."):args("*"):convert(tonumber)
--    passer:option("--dpdk-config", "DPDK config file")
    parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
end

local function master(arg0, ...)
	memory.testAllocationSpace()
	LIBMOON_TASK_NAME = "master"

    multiargs = dashdashSplitArgs(...)

    if not multiargs[1] then
        return
    end

    libmoon.config.userscript = arg0 -- FIXME: should not be used
    libmoon.setupPaths() -- need the userscript first because we want to use the path
	libmoon.config.dpdkArgs = {} -- FIXME

    local pargs = {}
    local main_defaults = {}
    
    for i, args in ipairs(multiargs) do
        local parser = argparse()
        local taskInfo = {}
        local defaults = {}
        if i == 1 then -- master
            parser:name(arg0)
            configure_main(parser)
        else -- task
            local file = args[1]
            table.remove(args, 1)
            parser:name(file)
            parser:option("-n", "Number of examples of task."):default(1):convert(tonumber)
            _G_saved = _G
            -- run the userscript
            local ok = run(file)
            if not ok then
                return
            end

            if _G.configure then
                parser:args(unpack(args))
                _G.configure(parser)
            end

            defaults = _G.defaults or {}
            taskInfo.task = _G.task
            taskInfo.file = file
            -- _G.configure = nil
            -- _G.defaults = nil
            -- _G.task = nil
            _G = _G_saved
        end
        configure_common(parser, main_defaults, defaults)
        parser:args(unpack(args))
        taskInfo = mergeTables(parser:parse(), taskInfo)

        if i == 1 then
            main_defaults.rx_queues = taskInfo.rx_queues
            main_defaults.tx_queues = taskInfo.tx_queues
        end
        
        pargs[i-1] = taskInfo
    end

    local main_pargs = pargs[0]
    pargs[0] = nil

    local rxQueues = 0
    local txQueues = 0
    for i, taskInfo in ipairs(pargs) do
		taskInfo.rx_buf = taskInfo.rx_buf or taskInfo.buf or main_pargs.rx_buf or main_pargs.buf
		taskInfo.tx_buf = taskInfo.tx_buf or taskInfo.buf or main_pargs.tx_buf or main_pargs.buf
		taskInfo.buf = nil

		if not taskInfo.rx_queues or not taskInfo.tx_queues then
            log:fatal("Numbers of RX/TX queues for task '%s' must be set. Use --rx-queues, --tx-queues options or set defaults.rx_queues, defaults.tx_queues", taskInfo.file)
        end
        rxQueues = rxQueues + taskInfo.rx_queues * taskInfo.n
        txQueues = txQueues + taskInfo.tx_queues * taskInfo.n
    end
    if rxQueues == 0 then rxQueues = 1 end
    if txQueues == 0 then txQueues = 1 end

    if not libmoon.config.skipInit then
		if not dpdk.init() then
			log:fatal("Could not initialize DPDK")
		end
	end

    local taskNum = 0
	for _, dev in ipairs(main_pargs.dev) do
        local rxNum = 0
        local txNum = 0
		local dev = device.config{port = dev, txQueues = txQueues, rxQueues = rxQueues}
		dev:wait()

        for _, taskInfo in ipairs(pargs) do
            libmoon.config.userscript = taskInfo.file -- NB

            for _ = 1, taskInfo.n do
                rxInfo = {}
                for i = 1, taskInfo.rx_queues do
                    rxInfo[i] = {queue = dev:getRxQueue(rxNum), bufSize = nil}
                    rxNum = rxNum + 1
                end
                txInfo = {}
                for i = 1, taskInfo.tx_queues do
                    txInfo[i] = {queue = dev:getTxQueue(txNum), bufSize = nil}
                    txNum = txNum + 1
                end

                mg.startTask("task", taskNum, txInfo, rxInfo, taskInfo) -- FIXME
                taskNum = taskNum + 1
            end
        end
	end
	mg.waitForTasks()
end

function main(task, exe, ...)
    if task == "master" then
        if string.find(exe, "/MoonGen$") ~= nil then
            libmoon_main(task, exe, ...)
        elseif string.find(exe, "/tman$") ~= nil then
            master(exe, ...)
        else
            log:fatal("Unknown executable file name '%s'. Only 'tman' and 'MoonGen' are recognized as valid names. Are we using symlinked or copied file?", exe)
        end
    else
        libmoon_main(task, exe, ...)
    end
end
