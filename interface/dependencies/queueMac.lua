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
  return device.get(flow[tbl[2] .. "_dev"]):getMac(true)
end

return dependency
