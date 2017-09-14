local device = require "device"

local feature = {}

function feature.env(env)
  function env.txQueue()
    return { "queueMac", "tx" }
  end

  function env.rxQueue()
    return { "queueMac", "rx" }
  end
end

function feature.debug(tbl)
  return string.format("Mac address of %s device.", tbl[2])
end

function feature.getValue(flow, tbl)
  return device.get(flow[tbl[2] .. "_dev"]):getMac(true)
end

return feature
