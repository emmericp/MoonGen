local _safe_methods = {}
for v in string.gmatch([[
  string table math
  getmetatable
  ipairs next pairs
  rawequal rawget rawlen
  tonumber tostring type
]], "%S+") do
  _safe_methods[v] = _G[v]
end

return function(tbl, ...)
  require "configenv.setup" (tbl, ...)
  require "configenv.range" (tbl, ...)
  require "configenv.util" (tbl, ...)
  return setmetatable(tbl, { __index = _safe_methods }), ...
end
