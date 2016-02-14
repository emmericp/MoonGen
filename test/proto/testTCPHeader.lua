describe("TCP packet class", function()
	local ffi = require "ffi"
	local pkt = require "proto.proto"
	it("should set TCP", function()
		local raw = ffi.new("struct tcp_header")
		local set = ffi.new("struct tcp_header")

		raw.src = hton16(1234)
		set:setSrcPort(1234)
		assert.are.same(raw.src, set.src)
		
		raw.dst = hton16(5678)
		set:setDstPort(5678)
		assert.are.same(raw.dst, set.dst)
		
		raw.seq = hton(122334)
		set:setSeqNumber(122334)
		assert.are.same(raw.seq, set.seq)

		raw.ack = hton(566778)
		set:setAckNumber(566778)
		assert.are.same(raw.ack, set.ack)

		-- TODO offset reserved flags
		
		raw.window = hton16(9876)
		set:setWindow(9876)
		assert.are.same(raw.window, set.window)
		
		raw.cs = hton16(1928)
		set:setChecksum(1928)
		assert.are.same(raw.cs, set.cs)

		raw.urg = hton16(3746)
		set:setUrgentPointer(3746)
		assert.are.same(raw.urg, set.urg)
	end)
	it("should set/get with named args (TCPv4)", function()
		local pkt = ffi.new("struct __ethernet_eth__ip4_ip4__tcp_tcp")	
		
		local tcpSrc			= 456
		local tcpDst			= 789
		local tcpSeqNumber		= 1337
		local tcpAckNumber		= 4207
		local tcpDataOffset		= 0xf
		local tcpReserved		= 0x11
		local tcpFlags			= 0x22
		local tcpWindow			= 23
		local tcpChecksum		= 0x9876
		local tcpUrgentPointer	= 91
		local tcpUrg			= 1
		local tcpAck			= 0
		local tcpPsh			= 0
		local tcpRst			= 0
		local tcpSyn			= 1
		local tcpFin			= 0

		local args = pkt:get()
		args.tcpSrc = tcpSrc 
		args.tcpDst = tcpDst 
		args.tcpSeqNumber = tcpSeqNumber
		args.tcpAckNumber = tcpAckNumber 
		args.tcpDataOffset = tcpDataOffset
		args.tcpReserved = tcpReserved
		args.tcpFlags = tcpFlags
		args.tcpWindow = tcpWindow 
		args.tcpChecksum = tcpChecksum 
		args.tcpUrgentPointer = tcpUrgentPointer
		args.tcpUrg = tcpUrg
		args.tcpAck	= tcpAck
		args.tcpPsh = tcpPsh
		args.tcpRst = tcpRst
		args.tcpSyn = tcpSyn
		args.tcpFin = tcpFin

		pkt:fill(args)
		assert.are.same(tcpSrc, pkt.tcp:getSrcPort())
		assert.are.same(tcpDst, pkt.tcp:getDstPort())	
		assert.are.same(tcpSeqNumber, pkt.tcp:getSeqNumber())	
		assert.are.same(tcpAckNumber, pkt.tcp:getAckNumber())	
		assert.are.same(tcpDataOffset, pkt.tcp:getDataOffset())	
		assert.are.same(tcpReserved, pkt.tcp:getReserved())	
		assert.are.same(tcpFlags, pkt.tcp:getFlags())	
		assert.are.same(tcpWindow, pkt.tcp:getWindow())	
		assert.are.same(tcpChecksum, pkt.tcp:getChecksum())	
		assert.are.same(tcpUrgentPointer, pkt.tcp:getUrgentPointer())	
		assert.are.same(tcpUrg, pkt.tcp:getUrg())	
		assert.are.same(tcpAck, pkt.tcp:getAck())	
		assert.are.same(tcpPsh, pkt.tcp:getPsh())	
		assert.are.same(tcpRst, pkt.tcp:getRst())	
		assert.are.same(tcpSyn, pkt.tcp:getSyn())	
		assert.are.same(tcpFin, pkt.tcp:getFin())	

		local args2 = pkt:get()
		assert.are.same(args, args2)
	end)	
end)

