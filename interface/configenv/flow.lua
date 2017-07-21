local Flow = {}

function Flow.new(name, tbl)
	local parent = tbl.parent
	local self = {
		name = name,
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
