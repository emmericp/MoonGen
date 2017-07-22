local lfs = require "lfs"
local log = require "log"

local errors = require "errors"
local validator = require "validator"

local crawl = {}
local devnum
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
		log:error("Flow %q not found.", name)
		return
	end

	local val = validator()
	f:validate(val)
	if not val.valid then
		log:error("Flow %q is invalid:", name)
		val:print(log.warn, log)
		return
	end

	tx, rx = tonumber(tx), tonumber(rx)
	if not tx or tx >= devnum then
		log:error("Transmit port for flow %q needs to be a valid device number.", name)
		return
	elseif not rx or rx >= devnum then
		log:error("Receive port for flow %q needs to be a valid device number.", name)
		return
	end

	local options = {}
	for i,v in string.gmatch(optstring, "([^=,]+)=([^,]+)") do
		options[i] = v
	end

	return setmetatable({ options = options, tx = tx, rx = rx }, { __index = f })
end

function crawl.passFlow(f)
	if type(f) == "string" then
		f = crawl.getFlow(f)
	end
	return { name = f.name, file = f.file, options = f.options }
end

function crawl.receiveFlow(fdef)
	_parse_file(fdef.file)
	local f = setmetatable({ options = fdef.options }, { __index = flows[fdef.name] })
	f:prepare()
	return f
end

return setmetatable(crawl, {
	__call = function(_, baseDir)
		devnum = require("device").numDevices()

		baseDir = baseDir or "flows"
		for f in lfs.dir(baseDir) do
			f = baseDir .. "/" .. f
			if lfs.attributes(f, "mode") == "file" then
				_parse_file(f)
			end
		end

		local cnt = errhnd:count()
		if cnt > 0 then
			log:error("%d errors found while crawling config:", cnt)
			errhnd:print(log.warn, log)
		end

		return flows
	end
})
