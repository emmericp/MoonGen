describe("UDP class", function()
	local pkt = require "packet"
	local ffi = require "ffi"
	it("should set", function()
		local raw = ffi.new("struct udp_header")
		local set = ffi.new("struct udp_header")
		
		raw.src = hton16(1117)
		set:setSrcPort(1117)
		assert.are.same(raw.src, set.src)
		
		raw.dst = hton16(2223)
		set:setDstPort(2223)
		assert.are.same(raw.dst, set.dst)
		
		raw.len = hton16(55)
		set:setLength(55)
		assert.are.same(raw.len, set.len)
		
		raw.cs = hton16(5000)
		set:setChecksum(5000)
		assert.are.same(raw.cs, set.cs)

	end)

end)

