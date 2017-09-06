local lfs = require "lfs"
local log = require "log"

local errors = require "errors"
local validator = require "validator"

local crawl = {}
local errhnd = errors()

local _current_file
local flows = {}
local _env_flows = setmetatable({}, {
	__newindex = function(_, key, val)
		if flows[key] then
			errhnd(3, "Duplicate flow %q. Also in file %s.", key, flows[key].file)
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

function crawl.getFlow(name, options)
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

	local opterrors = errors()
	f:testOptions(options, opterrors)
	if opterrors:count() > 0 then
		log:error("Options for flow %q are invalid:", name)
		opterrors:print(false, log.warn, log)
		return
	end

	return setmetatable({ options = options }, { __index = f })
end

function crawl.cloneFlow(flow)
	local f = {}

	for i,v in pairs(flow) do
		f[i] = v
	end

	return setmetatable(f, getmetatable(flow))
end

function crawl.passFlow(f)
	if type(f) == "string" then
		f = crawl.getFlow(f)
	end
	return { name = f.name, file = f.file, options = f.options }
end

function crawl.receiveFlow(fdef)
	if not flows[fdef.name] then
		_parse_file(fdef.file)
	end

	local f = setmetatable({ options = fdef.options }, { __index = flows[fdef.name] })
	f:prepare()
	return f
end

return setmetatable(crawl, {
	__call = function(_, baseDir, suppressWarnings)
		baseDir = baseDir or "flows"
		for f in lfs.dir(baseDir) do
			f = baseDir .. "/" .. f
			if lfs.attributes(f, "mode") == "file" then
				_parse_file(f)
			end
		end

		local cnt = errhnd:count()
		if cnt > 0 and not suppressWarnings then
			log:error("%d errors found while crawling config:", cnt)
			errhnd:print(true, log.warn, log)
		end

		return flows
	end
})
