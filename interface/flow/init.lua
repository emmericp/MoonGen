local lfs = require "syscall.lfs"
local log = require "log"

local configenv = require "configenv"
local options = require "options"
local errors = require "errors"

local Flow = require "flow.instance"
local Packet = require "flow.packet"

local mod = { flows = {} }

local env = configenv.env
function env.Flow(tbl)
		if type(tbl) ~= "table" then
			env.error("Invalid usage of Flow. Try Flow{...)")
			return
		end

		-- check name, disallow for characters that
		-- - would complicate shell argument parsing ( ;)
		-- - interfere with flow parameter syntax (/:,)
		local name = tbl[1]
		local t = type(name)
		if  t ~= "string" then
			env.error("Invalid flow name. String expected, got %s.", t)
			name = nil
		elseif name == "" then
			env.error("Flow name cannot be empty.")
			name = nil
		elseif string.find(name, "[ ;/:,]") then
			env.error("Invalid flow name %q. Names cannot include the characters ' ;/:,'.", name)
			name = nil
		end

		-- find instace of parent flow
		local parent = tbl.parent
		t = type(parent)
		if t == "string" then
			parent = mod.flows[parent]
			env.error:assert(parent, "Unknown parent %q of flow %q.", parent, name)
		elseif t ~= "table" and t ~= "nil" then
			env.error("Invalid value for parent of flow %q. String or flow expected, got %s.", name, t)
			parent = nil
		end

		local packet = tbl[2]
		if env.error:assert(packet, "Flow %q does not have a valid packet.", name) and parent then
			packet:inherit(parent.packet)
		end

		-- process options
		tbl[1], tbl[2], tbl.parent = nil, nil, nil
		for i in pairs(tbl) do
			env.error:assert(options[i], "Unknown option %q.", i)
		end

		local opts, parent_opts = {}, parent and parent.options or {}
		for i in pairs(options) do
			opts[i] = tbl[i] or parent_opts[i]
		end

		-- ready to assemble flow prototype
		local flow = { name = name, file = env._FILE, parent = parent, packet = packet, options = opts}

		-- attempt to add to global flow list
		if flow.name then
			local test = mod.flows[name]
			if test then
				env.error:assert(not test, 3, "Duplicate flow %q. Also in file %s.", name, test.file)
			else
				mod.flows[name] = flow
			end
		end

		return flow
end

local packetmsg = "Invalid usage of Packet. Try Packet.<Proto>{...}."
local function _packet_error() env.error(packetmsg) end
env.Packet = setmetatable({}, {
	__newindex = _packet_error,
	__call = _packet_error,
	__index = function(_, proto)
		if type(proto) ~= "string" then
			env.error(packetmsg)
			return function() end
		end

		return function(tbl)
			if type(tbl) ~= "table" then
				env.error(packetmsg)
			else
				return Packet.new(proto, tbl, env.error)
			end
		end
	end
})

local function printError(silent, ...)
	if not silent then
		log:error(...)
	end
end

local function finalizeErrHnd(silent, error, msg, ...)
	if silent then return end
	local cnt = error:count()
	if cnt > 0 then
		log:error(msg, cnt, ...)
		error:print(true, log.warn, log)
	end
end

function mod.crawlDirectory(baseDir, silent)
	configenv:setErrHnd()

	baseDir = baseDir or "flows"
	for f in lfs.dir(baseDir) do
		f = baseDir .. "/" .. f
		if lfs.attributes(f, "mode") == "file" then
			configenv:parseFile(f)
		end
	end

	finalizeErrHnd(silent, configenv:error(),
		"%d errors found while processing directory %s:", baseDir)
end

function mod.crawlFile(filename, silent)
	configenv:setErrHnd()
	configenv:parseFile(filename)

	finalizeErrHnd(silent, configenv:error(),
		"%d errors found while processing file %s:", filename)
end

function mod.getInstance(name, file, cli_options, overwrites, properties, silent, final)
	local error = errors()
	error.defaultLevel = -1

	local flow = {
		restore = { options = cli_options, overwrites = overwrites },
		proto = mod.flows[name], -- packet = proto.packet,
		results = {}, properties = properties or {}
	}
	setmetatable(flow, Flow)

	-- find flow prototype
	if file and not flow.proto then
		configenv:setErrHnd()
		configenv:parseFile(file)
		finalizeErrHnd(silent, configenv:error(),
			"%d errors found while processing extra file %s:", file)

		flow.proto = mod.flows[name]
	end

	if not flow.proto then
		return printError(silent, "Flow %q not found.", name)
	end

	-- find or create packet
	flow.packet = flow.proto.packet
	if overwrites and overwrites ~= "" then
		configenv:setErrHnd(error)
		flow.packet = configenv:parseString(
			("return Packet.%s{%s}"):format(flow.packet.proto, overwrites),
			("Overwrites for flow %q."):format(name)
		)
	else
		flow.packet = Packet.new(flow.proto.packet.proto, {})
	end

	if not flow.packet then
		return printError(silent, "Invalid overwrite for flow %q.", name)
	end
	flow.packet:inherit(flow.proto.packet)

	-- warn about unknown options
	for i in pairs(cli_options) do
		error:assert(options[i], "Unknown option %q.", i)
	end

	-- process options
	local results = flow.results
	for i, opt in pairs(options) do
		error:setPrefix("Option '%s': ", i)
		local v = cli_options[i] or flow.proto.options[i]
		results[i] = opt.parse(flow, v, error)
	end

	-- prepare flow
	error:setPrefix()
	flow:prepare(error, final)

	finalizeErrHnd(silent, error, "%d errors found while processing flow %q.", name)

	if error.valid then
		return flow
	end
end

function mod.restore(flow)
	local p, r = flow.proto, flow.restore
	return mod.getInstance(p.name, p.file, r.options, r.overwrites, flow.properties, true, true)
end

return mod
