describe("ARP packet class", function()
	local ffi = require "ffi"
	local pkt = require "proto.arp"
	it("should set ARP", function()
		local raw = ffi.new("struct arp_header")
		local set = ffi.new("struct arp_header")

		raw.hrd = hton16(1234)
		set:setHardwareAddressType(1234)
		assert.are.same(raw.hrd, set.hrd)
		
		raw.pro = hton16(5678)
		set:setProtoAddressType(5678)
		assert.are.same(raw.pro, set.pro)
		
		raw.hln = 642
		set:setHardwareAddressLength(642)
		assert.are.same(raw.hln, set.hln)

		raw.pln = 753
		set:setProtoAddressLength(753)
		assert.are.same(raw.pln, set.pln)

		raw.op = hton16(9876)
		set:setOperation(9876)
		assert.are.same(raw.op, set.op)
		
		raw.sha:setString("12:34:56:78:9a:bc")
		set:setHardwareSrcString("12:34:56:78:9a:bc")
		assert.are.same(raw.sha, set.sha)

		raw.tha:setString("ff:ee:dd:cc:bb:aa")
		set:setHardwareDstString("ff:ee:dd:cc:bb:aa")
		assert.are.same(raw.tha, set.tha)

		raw.spa:setString("100.255.90.12")
		set:setProtoSrcString("100.255.90.12")
		assert.are.same(raw.spa, set.spa)

		raw.tpa:setString("153.164.120.1")
		set:setProtoDstString("153.164.120.1")
		assert.are.same(raw.tpa, set.tpa)
	end)

	it("should set/get with named args (ARP)", function()
		-- TODO
	end)	
end)


