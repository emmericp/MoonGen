local mod = {}

local phobos = require "phobos"

-- add moongen-specific functions here

setmetatable(mod, {__index = phobos})

return mod
