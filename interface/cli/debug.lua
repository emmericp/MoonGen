local ffi     = require "ffi"

local parse = require "flowparse"
local Flow = require "flow"

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
		getBytes = function(self) return self.data end,
		getData = function(self)
			return voidPtrType(self.data) -- luacheck: globals voidPtrType
		end,
	}
})

local function _print_debug(args)
	Flow.crawlDirectory(args.config)

	local fparse = parse(args.flow, math.huge)
	local flow = Flow.getInstance(fparse.name, fparse.file, fparse.options, fparse.overwrites,
		{ tx = {1}, rx = {1} })

	if not flow then return end

	local length = flow:packetSize()
	local array = ffi.new("uint8_t[?]", length)
	local test = debug_packet(length, array)

	print(string.format("Flow: \27[1m%s\27[0m\n", fparse.name))

	local dv = flow.packet.dynvars
	if #dv > 0 then
		local dynvar_out = {"Dynamic: "}
		for _,v in ipairs(dv) do
			table.insert(dynvar_out, v.pkt)
			table.insert(dynvar_out, string.upper(string.sub(v.var, 1, 1)))
			table.insert(dynvar_out, string.sub(v.var, 2))
			table.insert(dynvar_out, ", ")
		end
		dynvar_out[#dynvar_out] = "\n"
		print(table.concat(dynvar_out))
	end

	local dependencies = flow.packet.depvars
	if #dependencies > 0 then
		local dep_out = {"Environment dependent:\n"}
		for i,v in pairs(dependencies) do
			table.insert(dep_out, string.rep(" ", 4))
			table.insert(dep_out, i)
			table.insert(dep_out, " => ")
			table.insert(dep_out, v.dep.debug(v.tbl))
			table.insert(dep_out, "\n")
		end
		print(table.concat(dep_out))
	end

	local pkt = flow:fillBuf(test)
	if flow.updatePacket then
		for _ = 1, args.count do
			flow:updateBuf(test):dump(length)
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
