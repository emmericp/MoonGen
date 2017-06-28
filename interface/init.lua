local cp = require "configparse"

function configure(parser)
  parser:description("Configuration based interface for MoonGen.")
  parser:option("-c --config", "Config file directory."):default("flows")
	parser:argument("txDev", "Device to transmit from."):convert(tonumber)
	parser:argument("rxDev", "Device to receive from."):convert(tonumber)
  parser:argument("flows", "List of flow names."):args "+"
end

function master(args)
  cp(args.config)
  for _,v in ipairs(args.flows) do
    print(cp[v][1])
  end
end
