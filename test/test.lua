describe("IPv6 class", function()
	local pkt = require "packet"
	it("should parse", function()
		local ip = parseIP6Address("0123:4567:89AB:CDEF:1011:1213:1415:1617")
		assert.are.same(ip.uint32[0], 0x14151617)
		assert.are.same(ip.uint32[1], 0x10111213)
		assert.are.same(ip.uint32[2], 0x89ABCDEF)
		assert.are.same(ip.uint32[3], 0x01234567)
		print "hello, world!"
	end)
	it("should do arithmetic", function()
		local ip = parseIP6Address("0000:0000:0000:0000:0000:0000:0000:0000")
		ip = ip + 1
		assert.are.same(ip.uint32[0], 1)
		assert.are.same(ip.uint32[1], 0)
		assert.are.same(ip.uint32[2], 0)
		assert.are.same(ip.uint32[3], 0)
		ip = ip + 0xFFFFFFFFFFFFFFFFULL
		assert.are.same(ip.uint32[0], 0)
		assert.are.same(ip.uint32[1], 0)
		assert.are.same(ip.uint32[2], 1)
		assert.are.same(ip.uint32[3], 0)
		local subByAdd = ip + (-1)
		assert.are.same(subByAdd.uint32[0], 0xFFFFFFFF)
		assert.are.same(subByAdd.uint32[1], 0xFFFFFFFF)
		assert.are.same(subByAdd.uint32[2], 0)
		assert.are.same(subByAdd.uint32[3], 0)
		local subBySub = ip -1
		assert.are.same(subBySub.uint32[0], 0xFFFFFFFF)
		assert.are.same(subBySub.uint32[1], 0xFFFFFFFF)
		assert.are.same(subBySub.uint32[2], 0)
		assert.are.same(subBySub.uint32[3], 0)
	end)

end)

