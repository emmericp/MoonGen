local lfs = require "syscall.lfs"

local errors = require "errors"

local mod = { env = {} }

local _safe_methods = {}
for v in string.gmatch([[
	string table math
	getmetatable setmetatable
	ipairs next pairs
	rawequal rawget rawlen
	tonumber tostring type
]], "%S+") do
	_safe_methods[v] = _G[v]
end
setmetatable(mod.env, { __index = _safe_methods })

require "configenv.range" (mod.env)
require "configenv.util" (mod.env)

for _,v in pairs(require "dependencies") do
	v.env(mod.env)
end

function mod:setErrHnd(hnd)
	self.env.error = hnd or errors()
end

function mod:error()
	return self.env.error
end

local function run(self, file, f, msg)
	assert(self.env.error, "No error handler set.")

	if not f then
		self:error()(0, msg)
		return
	end

	self.env._FILE = file
	return setfenv(f, self.env)()
end

local ffi = require "ffi"

local fileIndex = {}
local function getIndex(path)
	-- dev returns a struct in ljsyscall lfs with methods to parse minor/major; .device is just the raw id
	return ("%d_%d"):format(lfs.attributes(path, "dev").device, lfs.attributes(path, "ino"))
end

function mod:parseFile(filename)
	local idx = getIndex(filename)
	if not fileIndex[idx] then
		fileIndex[idx] = true
		run(self, filename, loadfile(filename))
	end
end

function mod:parseString(string, chunkname)
	return run(self, nil, loadstring(string, chunkname or "config string"))
end

return mod
