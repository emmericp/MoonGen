describe("TCP packet class", function()
	local ffi = require "ffi"
	local pkt = require "packet"
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
		local pkt = ffi.new("struct tcp_packet")	
		
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
		local tcpURG			= 1
		local tcpACK			= 0
		local tcpPSH			= 0
		local tcpRST			= 0
		local tcpSYN			= 1
		local tcpFIN			= 0

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
		args.tcpURG = tcpURG
		args.tcpACK	= tcpACK
		args.tcpPSH = tcpPSH
		args.tcpRST = tcpRST
		args.tcpSYN = tcpSYN
		args.tcpFIN = tcpFIN

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
		assert.are.same(tcpURG, pkt.tcp:getURG())	
		assert.are.same(tcpACK, pkt.tcp:getACK())	
		assert.are.same(tcpPSH, pkt.tcp:getPSH())	
		assert.are.same(tcpRST, pkt.tcp:getRST())	
		assert.are.same(tcpSYN, pkt.tcp:getSYN())	
		assert.are.same(tcpFIN, pkt.tcp:getFIN())	

		local args2 = pkt:get()
		assert.are.same(args, args2)
	end)	
end)

