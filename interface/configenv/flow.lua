local Flow = {}

function Flow.new(name, tbl)
	local parent = tbl.parent
	local self = {
		name = name,
		-- TODO figure out actual queue requirements
		tx_txq = 1, tx_rxq = 1, rx_txq = 1, rx_rxq = 1,
		packet = tbl[2]:inherit(parent and parent.packet)
	}

	if parent then
		self.parent = parent.name
		-- NOTE add copy opertations here
	end
	return setmetatable(self, { __index = Flow })
end

function Flow:validate(val)
	return self.packet:validate(val) -- TODO more validation
end

return Flow
