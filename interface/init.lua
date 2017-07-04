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
  for _,fname in ipairs(args.flows) do
    local f = flowcfg[fname]
    if not f then
      print("Flow " .. fname .. " not found.")
    else
      for i,v in pairs(f[1].fillTbl) do
        print(i, v)
      end
      print(string.rep("-", 50))
      for i = 1, 2 do
        for _,v in ipairs(f[1].dynvars) do
          print(table.concat{"pkt.", v.pkt, ".", v.var, " = ", tostring(v.func())})
        end
      end
    end
  end
end
