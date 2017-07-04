local lfs = require "lfs"

local flows = {}
local baseDir = "flows"

local _env = require "configenv" ({}, flows)
local function _parse_file(filename)
  local f = loadfile(filename)
  setfenv(f, _env)()
end

return function()
  for f in lfs.dir(baseDir) do
    f = baseDir .. "/" .. f
    if lfs.attributes(f, "mode") == "file" then
      _parse_file(f)
    end
  end
  return flows
end
