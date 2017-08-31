local Flow = {}

local _option_list = {
	rate = require "configenv.flow.rate",
	ratePattern = require "configenv.flow.ratePattern",
	mode = require "configenv.flow.mode",
	timeLimit = require "configenv.flow.timeLimit",
	dataLimit = require "configenv.flow.dataLimit",
	packetLength = {
		parse = function(self, packetLength)
			self.psize = tonumber(packetLength) or self.packet.fillTbl.pktLength
		end,
		validate = function() end,
		test = function(_, error, packetLength)
			error:assert(type(tonumber(packetLength)) == "number",
				"Option 'packetLength': Value needs to be a valid integer.")
		end,
		description = "Redefine the actualy size of packets sent using the command line.",
		configHelp =  "Designed for command line usage only. Use pktLength in the Packet"
			.. " descriptor, when editing configuration files.",
		getHelp = function()
			return { { "<integer>", "New size in bytes." } }
		end
	},
}

function Flow.getOptionHelpString(help_printer)
	help_printer:section("Options")
	help_printer:body("List of options available when customizing flows using"
		.. " command line or configuration files.")

	help_printer:section("Units")
	help_printer:subsection("Size Units '\27[4m<prefix><unit>\27[0m'\n")
	help_printer:body("Prefix can be one of '\27[4m[k|M|G[i]]\27[0m'"
		.. " with the i marking an IEC-prefix using multiples of 1024 instead of 1000.")
	help_printer:body("Unit can be one of '\27[4m(B|bit|p)\27[0m',"
		.. " meaning byte, bit and packet respectively.")

	help_printer:subsection("Time Units")
	help_printer:body("Available time units are '\27[4m(ms|s|m|h)\27[0m'"
		.. " for millisecond, second, minute or hour.")

	for i,v in pairs(_option_list) do
		help_printer:section(i)
		help_printer:body(v.description)

		for _,fmt in ipairs(v.getHelp()) do
			help_printer:subsection(string.format("%s = \27[4m%s\27[0m", i, fmt[1]))
			help_printer:body(fmt[2])
		end

		if v.configHelp then
			help_printer:subsection("Configuration\n")
			help_printer:body(v.configHelp)
		end
	end
end

function Flow.new(name, tbl, error)
	local self = { name = name, packet = tbl[2], parent = tbl.parent }
	tbl[1], tbl[2], tbl.parent = nil, nil, nil

	-- TODO figure out actual queue requirements
	self.tx_txq, self.tx_rxq, self.rx_txq, self.rx_rxq = 1, 1, 1, 1

	-- check and copy options
	for i,v in pairs(tbl) do
		local opt = _option_list[i]

		if not opt then
			error(3, "Unknown field %q in flow %q.", i, name)
		elseif opt.test(self, error, v) then
			self[i] = v
		end
	end

	-- inherit packet and options
	local parent = self.parent
	if type(parent) == "table" then
		self.packet:inherit(parent.packet)
		for i in pairs(_option_list) do
			self[i] = self[i] or parent[i]
		end
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:getPacketLength(finalLength)
	if not self.psize then
		_option_list.packetLength.parse(self, self.options.packetLength or self.packetLength)
	end

	if finalLength then
		return self.psize + 4
	end

	return self.psize
end

function Flow:validate(val)
	self.packet:validate(val)
	for i,opt in pairs(_option_list) do
		opt.validate(self, val, self[i])
	end
end

function Flow:testOptions(options, error)
	for i,v in pairs(options) do
		local opt = _option_list[i]

		if not opt then
			error("Unknown field %q.", i)
		else
			opt.test(self, error, v)
		end
	end
end

function Flow:prepare()
	self.packet:prepare()
	for name, opt in pairs(_option_list) do
		opt.parse(self, self.options[name] or self[name])
	end
end

return Flow
