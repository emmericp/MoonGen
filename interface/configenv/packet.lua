local Packet = {}

function Packet.new(proto, tbl, error)
  local self = {
    proto = proto,
    fillTbl = {},
    dynvars = {}
  }

  for i,v in pairs(tbl) do
    local pkt, var = string.match(i, "^([%l%d]+)(%u[%l%d]*)$");

    if pkt then
      if type(v) == "function" then
        var = string.lower(var)
        table.insert(self.dynvars, {
          pkt = pkt, var = var, func = v
        })
        v = v() -- NOTE arp will execute in master
      end

      self.fillTbl[i] = v
    else
      error("Invalid packet field %q.", i) -- TODO add hint?
    end
  end

  return setmetatable(self, { __index = Packet })
end

function Packet:inherit(other)
  if other then
    for i,v in pairs(other.fillTbl) do
      if not self.fillTbl[i] then
        self.fillTbl[i] = v
      end
    end

    -- TODO dynvar inheritance
  end

  return self
end

function Packet:validate()
  return type(self.fillTbl.pktLength) == "number" -- TODO more validation
end

return Packet
