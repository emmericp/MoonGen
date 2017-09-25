local arp = require "proto.arp"

local dependency = {}

function dependency.env(env)
  function env.arp(ip, fallback, timeout)
    return { "arp", ip, fallback, timeout or 5 }
  end
end

function dependency.debug(tbl)
  local addr = tbl[2]
  if type(addr) == "number" then
    addr = ip4ToString(addr) -- luacheck: read globals ip4ToString
  elseif type(addr) == "cdata" then
    addr = addr:getString(true)
  end
  return string.format("Arp result for ip '%s'.", addr)
end

function dependency.getValue(_, tbl)
  return nil -- TODO arp.blockingLookup(tbl[2], tbl[4]) or tbl[3]
end

return dependency
