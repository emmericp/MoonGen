local lfs = require "lfs"

local errors = require "errors"

local crawl = {}
local errhnd = errors()

local _current_file
local flows = {}
local _env_flows = setmetatable({}, {
	__newindex = function(_, key, val)
		if flows[key] then
			errhnd(nil, "Duplicate flow %q. Also in file %s.", key, flows[key].file)
		end

		val.file = _current_file
		flows[key] = val
	end,
	__index = flows
})

local _env = require "configenv" ({}, errhnd, _env_flows)
local function _parse_file(filename)
	local f = loadfile(filename)
	_current_file = filename
	setfenv(f, _env)()
end

function crawl.passFlow(name)
	return { name = name, file = flows[name].file }
end

function crawl.receiveFlow(f)
	_parse_file(f.file)
	return flows[f.name]
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
