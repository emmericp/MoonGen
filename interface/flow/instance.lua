local Flow = {}
Flow.__index = Flow

function Flow:prepare(error, final)
	self.isDynamic = type(self.updatePacket) ~= "nil"
	self.packet:prepare(error, self, final)
end

function Flow:property(name)
	return self.properties[name]
end

function Flow:setProperty(name, val)
	self.properties[name] = val
end

function Flow:option(name)
	return self.results[name]
end

function Flow:fillBuf(buf)
	local pkt = self.packet.getPacket(buf)
	pkt:fill(self.packet.fillTbl)
	return pkt
end

function Flow:fillUpdateBuf(buf)
	local pkt = self.packet.getPacket(buf)
	pkt:fill(self.packet.fillTbl)
	self.updatePacket(self.packet.dynvars, pkt)
	return pkt
end

function Flow:updateBuf(buf)
	local pkt = self.packet.getPacket(buf)
	self.updatePacket(self.packet.dynvars, pkt)
	return pkt
end

function Flow:packetSize(checksum)
	return self.packet.fillTbl.pktLength + (checksum and 4 or 0)
end

function Flow:clone(properties)
	local clone = setmetatable({}, Flow)

	for i,v in pairs(self) do
		if i == "properties" then
			clone[i] = mergeTables({}, v, properties) -- luacheck: globals read mergeTables
		else
			clone[i] = v
		end
	end

	return clone
end

function Flow:getDelay()
	local cbr = self.results.rate
	if cbr then
		local psize = self:getPacketLength(true)
		-- cbr      => mbit/s        => bit/1000ns
		-- psize    => b/p           => 8bit/p
		return 8000 * psize / cbr -- => ns/p
	end
end

return Flow
