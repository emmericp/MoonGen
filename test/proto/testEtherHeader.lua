describe("Ethernet class", function()
	local pkt = require "packet"
	local ffi = require "ffi"
	it("should set", function()
		local raw = ffi.new("struct ethernet_header")
		local set = ffi.new("struct ethernet_header")
		
		raw.dst:setString("90:e2:ba:35:b5:81")
		set:setDstString("90:e2:ba:35:b5:81")
		for i = 0, 5 do
			assert.are.same(raw.dst.uint8[i], set.dst.uint8[i])
		end
		
		raw.src:setString("12:34:56:78:9a:bc")
		set:setSrcString("12:34:56:78:9a:bc")
		for i = 0, 5 do
			assert.are.same(raw.src.uint8[i], set.src.uint8[i])
		end
		
		raw.type = hton16(0x0800)
		set:setType(0x0800)
		assert.are.same(raw.type, set.type)
	end)

end)

