describe("MAC class", function()
	local pkt = require "packet"
	local ffi = require "ffi"
	it("should parse", function()
		local mac = parseMacAddress("00:11:22:33:44:55")
		assert.are.same(mac.uint8[0], 0x00)
		assert.are.same(mac.uint8[1], 0x11)
		assert.are.same(mac.uint8[2], 0x22)
		assert.are.same(mac.uint8[3], 0x33)
		assert.are.same(mac.uint8[4], 0x44)
		assert.are.same(mac.uint8[5], 0x55)
	end)
	it("should return in correct byteorder", function()
		local macString = "01:22:33:44:55:66"
		local mac = ffi.new("struct mac_address")
		mac:setString(macString)
		assert.are.same(macString, mac:getString())
	end)
	it("should support ==", function()
		local mac = parseMacAddress("00:11:22:33:44:55")
		local mac2 = parseMacAddress("00-11-22-33-44-55")
		assert.are.same(mac, mac2)
	end)

end)

