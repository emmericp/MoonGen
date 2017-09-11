local packet  = require "packet"
local ffi     = require "ffi"

local crawl = require "configcrawl"
local parse = require "flowparse"

local debug = {}

ffi.cdef[[
	typedef struct {
		size_t length;
		uint8_t* data;
	} debug_packet_t;
]]

local debug_packet = ffi.metatype("debug_packet_t", {
	__index = {
		getLength = function(self) return self.length end,
		getData = function(self)
			return voidPtrType(ffi.new("uint8_t*[1]", self.data)) -- luacheck: globals voidPtrType
		end,
	}
})

local function _print_debug(args)
	crawl(args.config)

	local name, _, _, opts = parse(args.flow, math.huge)
	local flow = crawl.getFlow(name, opts)
	flow:prepare()

	local length = flow:getPacketLength()
	local array = ffi.new("uint8_t[?]", length)
	local test = debug_packet(length, array)

	print(string.format("Flow: \27[1m%s\27[0m", name))

	local dv = flow.packet.dynvars

	local dynvar_out = {"Dynamic: "}
	for _,v in ipairs(dv) do
		table.insert(dynvar_out, v.pkt)
		table.insert(dynvar_out, string.upper(string.sub(v.var, 1, 1)))
		table.insert(dynvar_out, string.sub(v.var, 2))
		table.insert(dynvar_out, ", ")
	end
	dynvar_out[#dynvar_out] = "\n"
	print(table.concat(dynvar_out))

	local pkt =  packet["get" .. flow.packet.proto .. "Packet"](test)
	pkt:fill(flow.packet.fillTbl)

	if flow.updatePacket then
		for _ = 1, args.count do
			flow.updatePacket(flow.packet.dynvars, pkt)
			pkt:dump()
		end
	else
		if args.count > 1 then
			print("Multiple packets requested but flow is not dynamic.")
		end
		pkt:dump()
	end
end

function debug.configure(parser)
	parser:option("-c --config", "Config file directory."):default("flows")
	parser:option("-n --count", "Amount of variants to display."):default("1"):convert(tonumber)
	parser:argument("flow", "Name of the flow to display.")

	parser:action(function(args)
		_print_debug(args)
		os.exit(0)
	end)
end

return debug
