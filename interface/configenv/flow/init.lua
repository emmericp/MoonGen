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
		formatString = "<integer>",
		helpString   = "Resize packets when starting a flow."
	},
}

function Flow.getOptionHelpString()
	local result = {}

	for i,v in pairs(_option_list) do
		table.insert(result, i)
		table.insert(result, "=")
		table.insert(result, v.formatString)
		table.insert(result, "\n   ")
		table.insert(result, v.helpString)
		table.insert(result, "\n\n")
	end

	table.remove(result)

	return table.concat(result)
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
