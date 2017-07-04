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
    if lfs.attributes(f, "mode") == "file" then
      _parse_file(baseDir .. "/" .. f)
    end
  end
  return flows
end
