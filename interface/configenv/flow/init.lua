local Flow = {}

local _option_list = {
	rate = require "configenv.flow.rate"
}

function Flow.new(name, tbl, error)
	local self = { name = name, packet = tbl[2], parent = tbl.parent }
	tbl[1], tbl[2], tbl.parent = nil, nil, nil

	-- TODO figure out actual queue requirements
	self.tx_txq, self.tx_rxq, self.rx_txq, self.rx_rxq = 1, 1, 1, 1

	-- check and copy options
	for i,v in pairs(tbl) do
		local opt = _option_list[i]

		if opt then
			if (not opt.test) or opt.test(error, v) then
				self[i] = v
			end
		else
			error(3, "Unknown field %q in flow %q.", i, name)
		end
	end

	if type(self.parent) == "table" then
		local parent = self.parent
		self.packet:inherit(parent.packet)

		-- copy parent options
		for i in pairs(_option_list) do
			if not self[i] then
				self[i] = parent[i]
			end
		end
	end

	return setmetatable(self, { __index = Flow })
end

function Flow:validate(val)
	self.packet:validate(val)

	-- validate options
	for i,opt in pairs(_option_list) do
		local v = self[i]
		if v and opt.validate then
			opt.validate(val, v)
		end
	end
end

-- TODO test dynamic options

function Flow:prepare()
	for name, opt in pairs(_option_list) do
		local v = self.options[name] or self[name]
		if v then
			opt.parse(self, v)
		end
	end
end

return Flow
