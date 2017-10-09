local mg         = require "moongen"
local log        = require "log"


local base = debug.getinfo(1, "S").source:sub(2,-9) -- remove "init.lua"
package.path = ("%s;%s?.lua;%s?/init.lua"):format(package.path, base, base)

local Flow = require "flow"
local parse = require "flowparse"
local counter = require "counter"
local devmgr = require "devmgr"

local arpThread = require "threads.arp"
local loadThread = require "threads.load"
local deviceStatsThread = require "threads.deviceStats"
local countThread = require "threads.count"
local timestampThread = require "threads.timestamp"


function configure(parser) -- luacheck: globals configure
	parser:description("Configuration based interface for MoonGen.")

	local start = parser:command("start", "Send one or more flows.")
	start:option("-c --config", "Config file directory."):default("flows")
	start:option("-o --output", "Output directory (histograms etc.)."):default(".")
	start:argument("flows", "List of flow names."):args "+"

	require "cli" (parser)
end

function master(args) -- luacheck: globals master
	Flow.crawlDirectory(args.config)

	local devices = devmgr.newDevmgr()
	local flows = {}
	for _,arg in ipairs(args.flows) do
		local fparse = parse(arg, devices.max)
		-- TODO fparse.file, fparse.overwrites
		local f

		if #fparse.tx == 0 and #fparse.rx == 0 then
			log:error("Need to pass at least one tx or rx device.")
		else
			f = Flow.getInstance(fparse.name, fparse.file, fparse.options, fparse.overwrites, {
				counter = counter.new(),
				tx = fparse.tx, rx = fparse.rx
			})
		end

		if f then
			table.insert(flows, f)
			log:info("Flow %s => %#x", f.proto.name, f:option "uid")
		end
	end

	arpThread.prepare(flows, devices)
	loadThread.prepare(flows, devices)
	countThread.prepare(flows, devices)
	deviceStatsThread.prepare(flows, devices)
	timestampThread.prepare(flows, devices)

	if #loadThread.flows == 0 then--and #countThread.flows == 0 then
		log:error("No valid flows remaining.")
		return
	end

	devices:configure()

	arpThread.start(devices)
	deviceStatsThread.start(devices)
	countThread.start(devices)
	loadThread.start(devices)
	timestampThread.start(devices, args.output)

	mg.waitForTasks()
end
