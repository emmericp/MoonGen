local lfs = require "lfs"
local log = require "log"

local errors = require "errors"

local crawl = {}
local errhnd = errors()

local _current_file
local flows = {}
local _env_flows = setmetatable({}, {
	__newindex = function(_, key, val)
		if flows[key] then
			errhnd("Duplicate flow %q. Also in file %s.", key, flows[key].file)
		end

		val.file = _current_file
		flows[key] = val
	end,
	__index = flows
})

local _env = require "configenv" ({}, errhnd, _env_flows)
local function _parse_file(filename)
	local f, msg = loadfile(filename)
	if not f then
		errhnd(0, msg)
		return
	end

	_current_file = filename
	setfenv(f, _env)()
end

-- Flow syntax <name>:<tx>:<rx>{,<key>=<value>}
function crawl.getFlow(fname)
	local name, tx, rx, optstring = string.match(fname, "^([^:]+):([^:]+):([^,]+),?(.*)$")
	if not name then
		log:fatal("Invalid parameter: %q. Expected format: '<name>:<tx>:<rx>{,<key>=<value>}'.", fname)
	end

	local f = flows[name]

	if not f then
		log:fatal("Flow %q not found.", name)
	end

	tx, rx = tonumber(tx), tonumber(rx)
	if not tx then
		log:fatal("Transmit port for flow %q needs to be a valid number.", name)
	elseif not rx then
		log:fatal("Receive port for flow %q needs to be a valid number.", name)
	end

	local options = {}
	for i,v in string.gmatch(optstring, "([^=,]+)=([^,]+)") do
		options[i] = v
	end

	return setmetatable({ options = options, tx = tx, rx = rx }, { __index = f })
end

function crawl.validateFlow(f)
	if type(f) == "string" then
		f = crawl.getFlow(f)
	end

	return f and true or false -- TODO validation
end

function crawl.passFlow(f)
	if type(f) == "string" then
		f = crawl.getFlow(f)
	end
	return { name = f.name, file = f.file, options = f.options }
end

function crawl.receiveFlow(f)
	_parse_file(f.file)
	return setmetatable({ options = f.options }, { __index = flows[f.name] })
end

return setmetatable(crawl, {
	__call = function(_, baseDir)
		baseDir = baseDir or "flows"
		for f in lfs.dir(baseDir) do
			f = baseDir .. "/" .. f
			if lfs.attributes(f, "mode") == "file" then
				_parse_file(f)
			end
		end

		errhnd:print()
		return flows
	end
})
