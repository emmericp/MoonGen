local configparse = {}
local baseDir = "flows"

local _env = require "configenv" ({}, flows)
local function _parse_file(filename)
  loadfile(filename, bt, _env)
end

local mt = {}

function mt.__call(_, dir)
  baseDir = dir
end

function mt.__index(tbl, key)
  local f = _parse_file(baseDir + "/" key + ".lua")
  tbl[key] = f
  return f
end

return setmetatable(configparse, mt)
