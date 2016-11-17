local mod = {}

local lm = require "libmoon"

-- add moongen-specific functions here

setmetatable(mod, {__index = lm})

return mod
