describe("IPv4 class", function()
	local pkt = require "packet"
	it("should parse", function()
		local ip = parseIP4Address("1.2.3.4")
		assert.are.same(ip.uint32, 0x04030201)
	end)
	it("should return in correct byteorder", function()
		local ip_string = "123.456.789.42"
		local ip = parseIP4Address(ip_string)
		assert.are.same(ip.getString(), ip_string)
	end)
	it("should support ==", function()
		local ip = parseIP4Address("123.456.789.42")
		local ip2 = parseIP4Address("123.456.789.42")
		local ip3 = parseIP4Address("123.456.789.43")
		assert.are.same(ip, ip2)
		assert.are.not_same(ip, ip3)
		assert.are.not_same(ip, 0)
	end)
	it("should do arithmetic", function()
		local ip = parseIP4Address("0.0.0.0") + 1
		assert.are.same(ip, parseIP4Address("0.0.0.1"))
		ip = ip + 256
		assert.are.same(ip, parseIP4Address("0.0.1.1"))
		ip = ip - 2
		assert.are.same(ip, parseIP4Address("0.0.0.255"))
	end)

end)

