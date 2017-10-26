local device = require "device"

local dependency = {}

function dependency.env(env)
  function env.txQueue()
    return { "queueMac", "tx" }
  end

  function env.rxQueue()
    return { "queueMac", "rx" }
  end
end

function dependency.debug(tbl)
  return string.format("Mac address of %s device.", tbl[2])
end

function dependency.getValue(flow, tbl)
  local id = flow:property(tbl[2] .. "_dev") or flow:property(tbl[2])[1]
  return device.get(id):getMac(true)
end

return dependency
