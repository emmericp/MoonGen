describe("IP header class", function()
	local ffi = require "ffi"
	local pkt = require "packet"
	it("should set IPv4", function()
		local raw = ffi.new("struct ipv4_header")
		local set = ffi.new("struct ipv4_header")
		
		raw.verihl = 0x45
		set:setVersion()
		set:setHeaderLength()
		assert.are.same(raw.verihl, set.verihl)
		
		raw.verihl = 0x29
		set:setVersion(0x2)
		set:setHeaderLength(0x9)
		assert.are.same(raw.verihl, set.verihl)
		
		raw.tos = 10
		set:setTOS(10)
		assert.are.same(raw.tos, set.tos)
		
		raw.len = hton16(48)
		set:setLength()
		assert.are.same(raw.len, set.len)
		
		raw.id = hton16(2000)
		set:setID(2000)
		assert.are.same(raw.id, set.id)
		
		raw.frag = hton16(1000)
		set:setFragment(1000)
		assert.are.same(raw.frag, set.frag)
		
		raw.ttl	= 64
		set:setTTL()
		assert.are.same(raw.ttl, set.ttl)
		
		raw.protocol = 0x34
		set:setProtocol(0x34)
		assert.are.same(raw.protocol, set.protocol)
		
		raw.src:setString("192.168.1.1")
		set:setSrcString("192.168.1.1")
		assert.are.same(raw.src.uint32, set.src.uint32)
		
		raw.dst:setString("11.22.33.44")
		set:setDstString("11.22.33.44")
		assert.are.same(raw.dst.uint32, set.dst.uint32)
		
		-- TODO checksum
		--[[
		raw.cs = 0x????
		set:calculateChecksum()
		assert.are.same(raw.cs, set.cs) --]]
	end)
	
	it("should set IPv6", function()
		local raw = ffi.new("struct ipv6_header")
		local set = ffi.new("struct ipv6_header")
		
		raw.vtf = 96
		set:setVersion()
		set:setTrafficClass()
		set:setFlowLabel()
		assert.are.same(raw.vtf, set.vtf)
		
		--TODO
		--[[
		raw.vtf = ??
		set:setVersion(2)
		set:setTrafficClass(10)
		set:setFlowLabel(20)
		assert.are.same(raw.vtf, set.vtf) --]]
		
		raw.len = hton16(8)
		set:setLength()
		assert.are.same(raw.len, set.len)
		
		raw.nextHeader = 0x11
		set:setNextHeader()
		assert.are.same(raw.nextHeader, set.nextHeader)
		
		raw.ttl	= 64
		set:setTTL()
		assert.are.same(raw.ttl, set.ttl)
		
		raw.src:setString("fe80::10:11:12:13")
		set:setSrcString("fe80::10:11:12:13")
		assert.are.same(raw.src.uint64[0], set.src.uint64[0])
		assert.are.same(raw.src.uint64[1], set.src.uint64[1])
		
		raw.dst:setString("aabb::20:21:22:23")
		set:setDstString("aabb::20:21:22:23")
		assert.are.same(raw.dst.uint64[0], set.dst.uint64[0])
		assert.are.same(raw.dst.uint64[1], set.dst.uint64[1])
	end)
end)

