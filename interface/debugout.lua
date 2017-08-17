local memory  = require "memory"
local packet  = require "packet"

local crawl = require "configcrawl"
local parse = require "flowparse"

return function(args)
	crawl(args.config)

	local pool = memory.createMemPool()
	local buf = pool:bufArray(1)

	for _,arg in ipairs(args.flows) do
		local name, _, opts = parse(arg, math.huge)
		local flow = crawl.getFlow(name, opts)
		flow:prepare()

		buf:alloc(flow:getPacketLength())

		print(string.format("\n\n\27[1m%s\27[0m", name))

		local pkt = packet["get" .. flow.packet.proto .. "Packet"](buf[1])
		pkt:fill(flow.packet.fillTbl)

		if flow.updatePacket then
			for _ = 1, args.debug do
				flow:updatePacket(pkt)
				pkt:dump()
			end
		else
			if args.debug > 1 then
				print("Multiple packets requested but flow is not dynamic.")
			end
			pkt:dump()
		end

		buf:freeAll()
	end
end
