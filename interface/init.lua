package.path = package.path .. ";interface/?.lua;interface/?/init.lua"
local crawl = require "configcrawl"

function configure(parser)
  parser:description("Configuration based interface for MoonGen.")
  parser:option("-c --config", "Config file directory."):default("flows")
	parser:argument("txDev", "Device to transmit from."):convert(tonumber)
	parser:argument("rxDev", "Device to receive from."):convert(tonumber)
  parser:argument("flows", "List of flow names."):args "+"
end

function master(args)
  local flowcfg = crawl()
  for _,v in ipairs(args.flows) do
    print(flowcfg[v][1])
  end
end
