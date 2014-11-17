describe("MAC class", function()
	local pkt = require "packet"
	it("should parse", function()
		local mac = parseMACAddress("00:11:22:33:44:55")
		assert.are.same(mac.uint8[0], 0x55)
		assert.are.same(mac.uint8[1], 0x44)
		assert.are.same(mac.uint8[2], 0x33)
		assert.are.same(mac.uint8[3], 0x22)
		assert.are.same(mac.uint8[4], 0x11)
		assert.are.same(mac.uint8[5], 0x00)
	end)
	it("should support ==", function()
		local mac = parseMACAddress("00:11:22:33:44:55")
		local mac2 = parseMACAddress("00-11-22-33-44-55")
		assert.are.same(mac, mac2)
	end)

end)

