------------------------------------------------------------------------
--- @file tcp.lua
--- @brief Transmission control protocol (TCP) utility.
--- Utility functions for the tcp_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - TCP constants
--- - TCP header utility
--- - Definition of TCP packets
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"
local dpdkc = require "dpdkc"

require "utils"
require "headers"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format


------------------------------------------------------------------------------
---- TCP constants
------------------------------------------------------------------------------


------------------------------------------------------------------------------
---- TCP header
------------------------------------------------------------------------------

--- Module for tcp_header struct (see \ref headers.lua).
local tcpHeader = {}
tcpHeader.__index = tcpHeader

--- Set the source port.
--- @param int Port as 16 bit integer.
function tcpHeader:setSrcPort(int)
	int = int or 1025
	self.src = hton16(int)
end

--- Set the source port. Alias for setSrcPort
--- @param int Port as 16 bit integer.
function tcpHeader:setSrc(int)
	self:setSrcPort(int)
end

--- Retrieve the source port.
--- @return Port as 16 bit integer.
function tcpHeader:getSrcPort()
	return hton16(self.src)
end

--- Retrieve the source port. Alias for getSrcPort
--- @return Port as 16 bit integer.
function tcpHeader:getSrc()
	return self:getSrcPort()
end

--- Retrieve the source port.
--- @return Port in string format.
function tcpHeader:getSrcPortString()
	return self:getSrcPort()
end

--- Retrieve the source port. Alias getSrcPortString
--- @return Port in string format.
function tcpHeader:getSrcString()
	return self:getSrcPortString()
end

--- Set the destination port.
--- @param int Port as 16 bit integer.
function tcpHeader:setDstPort(int)
	int = int or 1024
	self.dst = hton16(int)
end

--- Set the destination port. Alias for setDstPort
--- @param int Port as 16 bit integer.
function tcpHeader:setDst(int)
	self:setDstPort(int)
end

--- Retrieve the destination port.
--- @return Port as 16 bit integer.
function tcpHeader:getDstPort()
	return hton16(self.dst)
end

--- Retrieve the destination port. Alias for getDstPort
--- @return Port as 16 bit integer.
function tcpHeader:getDst()
	return self:getDstPort()
end

--- Retrieve the destination port.
--- @return Port in string format.
function tcpHeader:getDstPortString()
	return self:getDstPort()
end

--- Retrieve the destination port. Alias for getDstPortString
--- @return Port in string format.
function tcpHeader:getDstString()
	return self:getDstPortString()
end

--- Set the sequence number.
--- @param int Sequence number as 8 bit integer.
function tcpHeader:setSeqNumber(int)
	int = int or 0
	self.seq = hton(int)
end

--- Retrieve the sequence number.
--- @return Seq number as 8 bit integer.
function tcpHeader:getSeqNumber()
	return hton(self.seq)
end

--- Retrieve the sequence number.
--- @return Sequence number in string format.
function tcpHeader:getSeqNumberString()
	return self:getSeqNumber()
end

--- Set the acknowledgement number.
--- @param int Ack number as 8 bit integer.
function tcpHeader:setAckNumber(int)
	int = int or 0
	self.ack = hton(int)
end

--- Retrieve the acknowledgement number.
--- @return Seq number as 8 bit integer.
function tcpHeader:getAckNumber()
	return hton(self.ack)
end

--- Retrieve the acknowledgement number.
--- @return Ack number in string format.
function tcpHeader:getAckNumberString()
	return self:getAckNumber()
end

--- Set the data offset.
--- @param int Offset as 4 bit integer. Header size is counted in 32 bit words (min. 5 (no options), max. 15)
function tcpHeader:setDataOffset(int)
	int = int or 5 
	int = band(lshift(int, 4), 0xf0) -- fill to 8 bits
	
	old = self.offset
	old = band(old, 0x0f) -- remove old value
	
	self.offset = bor(old, int)
end

--- Retrieve the data offset.
--- @return Offset as 4 bit integer.
function tcpHeader:getDataOffset()
	return band(rshift(self.offset, 4), 0x0f)
end

--- Retrieve the data offset.
--- @return Offset in string format.
function tcpHeader:getDataOffsetString()
	return format("0x%01x", self:getDataOffset())
end

--- Set the reserved field.
--- @param int Reserved field as 6 bit integer.
function tcpHeader:setReserved(int)
	int = int or 0
	-- offset  |   flags
	-- XXXXOOOO OOXXXXXX
	--     reserved

	-- first, offset field
	off = band(rshift(int, 2), 0x0f) -- fill to 8 bits (4 highest to 4 lowest bits)
	
	old = self.offset
	old = band(old, 0xf0) -- remove old value
	
	self.offset = bor(old, off)

	-- secondly, flags field
	fla = lshift(int, 6) -- fill to 8 bits (2 lowest to 2 highest bits)
	
	old = self.flags
	old = band(old, 0x3f) -- remove old values

	self.flags = bor(old, fla)
end

--- Retrieve the reserved field.
--- @return Reserved field as 6 bit integer.
function tcpHeader:getReserved()
	res = lshift(band(self.offset, 0x0f), 2) 	-- 4 lowest from offset to 4 highest from reserved
	res = bor(res, rshift(self.flags, 6)) 		-- 2 highest from flags to 2 lowest from reserved
	return res
end

--- Retrieve the reserved field.
--- @return Reserved field in string format.
function tcpHeader:getReservedString()
	return format("0x%02x", self:getReserved())
end

--- Set the flags.
--- @param int Flags as 6 bit integer.
--- @todo TODO RFC 3168 specifies new CWR and ECE flags (reserved reduced to 4 bit)
function tcpHeader:setFlags(int)
	int = int or 0

	int = band(int, 0x3f) -- fill to 8 bits
	
	old = self.flags
	old = band(old, 0xc0) -- remove old values

	self.flags = bor(old, int)
end

--- Retrieve the flags.
--- @return Flags as 6 bit integer.
function tcpHeader:getFlags()
	return band(self.flags, 0x3f)
end

--- Retrieve the flags.
--- @return Flags in string format.
function tcpHeader:getFlagsString()
	return format("0x%02x", self:getFlags())
end

--- Set the Urg flag.
function tcpHeader:setUrg()
	self.flags = bor(self.flags, 0x20)
end

--- Unset the Urg flag.
function tcpHeader:unsetUrg()
	self.flags = band(self.flags, 0xdf)
end

--- Retrieve the Urg flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getUrg()
	return rshift(band(self.flags, 0x20), 5)
end

--- Retrieve the Urg flag.
--- @return Flag in string format.
function tcpHeader:getUrgString()
	if self:getUrg() == 1 then
		return "URG"
	else
		return "X"
	end
end

--- Set the Ack flag.
function tcpHeader:setAck()
	self.flags = bor(self.flags, 0x10)
end

--- Unset the Ack flag.
function tcpHeader:unsetAck()
	self.flags = band(self.flags, 0xef)
end

--- Retrieve the Ack flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getAck()
	return rshift(band(self.flags, 0x10), 4)
end

--- Retrieve the Ack flag.
--- @return Flag in string format.
function tcpHeader:getAckString()
	if self:getAck() == 1 then
		return "ACK"
	else
		return "X"
	end
end

--- Set the Psh flag.
function tcpHeader:setPsh()
	self.flags = bor(self.flags, 0x08)
end

--- Unset the Psh flag.
function tcpHeader:unsetPsh()
	self.flags = band(self.flags, 0xf7)
end

--- Retrieve the Psh flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getPsh()
	return rshift(band(self.flags, 0x08), 3)
end

--- Retrieve the Psh flag.
--- @return Flag in string format.
function tcpHeader:getPshString()
	if self:getPsh() == 1 then
		return "PSH"
	else
		return "X"
	end
end

--- Set the Rst flag.
function tcpHeader:setRst()
	self.flags = bor(self.flags, 0x04)
end

--- Unset the Rst flag.
function tcpHeader:unsetRst()
	self.flags = band(self.flags, 0xfb)
end

--- Retrieve the Rst flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getRst()
	return rshift(band(self.flags, 0x04), 2)
end

--- Retrieve the Rst flag.
--- @return Flag in string format.
function tcpHeader:getRstString()
	if self:getRst() == 1 then
		return "RST"
	else
		return "X"
	end
end

--- Set the Syn flag.
function tcpHeader:setSyn()
	self.flags = bor(self.flags, 0x02)
end

--- Unset the Syn flag.
function tcpHeader:unsetSyn()
	self.flags = band(self.flags, 0xfd)
end

--- Retrieve the Syn flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getSyn()
	return rshift(band(self.flags, 0x02), 1)
end

--- Retrieve the Syn flag.
--- @return Flag in string format.
function tcpHeader:getSynString()
	if self:getSyn() == 1 then
		return "SYN"
	else
		return "X"
	end
end

--- Set the Fin flag.
function tcpHeader:setFin()
	self.flags = bor(self.flags, 0x01)
end

--- Unset the Fin flag.
function tcpHeader:unsetFin()
	self.flags = band(self.flags, 0xfe)
end

--- Retrieve the Fin flag.
--- @return Flag as 1 bit integer.
function tcpHeader:getFin()
	return band(self.flags, 0x01)
end

--- Retrieve the Fin flag.
--- @return Flag in string format.
function tcpHeader:getFinString()
	if self:getFin() == 1 then
		return "FIN"
	else
		return "X"
	end
end

--- Set the window field.
--- @param int Window as 16 bit integer.
function tcpHeader:setWindow(int)
	int = int or 0
	self.window = hton16(int)
end

--- Retrieve the window field.
--- @return Window as 16 bit integer.
function tcpHeader:getWindow()
	return hton16(self.window)
end

--- Retrieve the window field.
--- @return Window in string format.
function tcpHeader:getWindowString()
	return self:getWindow()
end

--- Set the checksum.
--- @param int Checksum as 16 bit integer.
function tcpHeader:setChecksum(int)
	int = int or 0
	self.cs = hton16(int)
end

--- Calculate and set the checksum.
--- If possible use checksum offloading instead.
--- @param data cdata object of the complete packet.
--- @param len	Length of the complete packet.
--- @param ipv4	True if its an IP4 packet. Default: true
--- @see pkt:offloadTcpChecksum
function tcpHeader:calculateChecksum(data, len, ipv4)
	-- first calculate checksum for the pseudo header
	-- and write it into the checksum field
	-- then, calculate remaining checksum of tcp segment
	-- deduct Ethernet and IP header length from total size
	if ipv4 then
		dpdkc.calc_ipv4_pseudo_header_checksum(data, 25) -- offset in 16bit integers (byte #50 for IP4)
		self:setChecksum(hton16(checksum(self, len - (14 + 20))))
	else
		dpdkc.calc_ipv6_pseudo_header_checksum(data, 30)
		self:setChecksum(hton16(checksum(self, len - (14 + 40))))
	end
end

--- Retrieve the checksum.
--- @return Checksum as 16 bit integer.
function tcpHeader:getChecksum()
	return hton16(self.cs)
end

--- Retrieve the checksum.
--- @return Checksum in string format.
function tcpHeader:getChecksumString()
	return format("0x%04x", self:getChecksum())
end

--- Set the urgent pointer.
--- @param int Urgent pointer as 16 bit integer.
function tcpHeader:setUrgentPointer(int)
	int = int or 0
	self.urg = hton16(int)
end

--- Retrieve the urgent pointer.
--- @return Urgent pointer as 16 bit integer.
function tcpHeader:getUrgentPointer()
	return hton16(self.urg)
end

--- Retrieve the urgent pointer.
--- @return Urgent pointer in string format.
function tcpHeader:getUrgentPointerString()
	return self:getUrgentPointer()
end

-- TODO how do we want to handle options (problem is tcp header variable length array of uint8[] followed by payload variable length array (uint8[]))
--[[function tcpHeader:setOptions(int)
	int = int or
	self. = int
end--]]

--- Set all members of the ip header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: Src, Dst, SeqNumber, AckNumber, DataOffset, Reserved, Flags, Urg, Ack, Psh, Rst, Syn, Fin, Window, Checksum, UrgentPointer
--- @param pre prefix for namedArgs. Default 'tcp'.
--- @code
--- fill() --- only default values
--- fill{ tcpSrc=1234, ipTTL=100 } --- all members are set to default values with the exception of tcpSrc
--- @endcode
function tcpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "tcp"

	self:setSrcPort(args[pre .. "Src"])
	self:setDstPort(args[pre .. "Dst"])
	self:setSeqNumber(args[pre .. "SeqNumber"])
	self:setAckNumber(args[pre .. "AckNumber"])
	self:setDataOffset(args[pre .. "DataOffset"])
	self:setReserved(args[pre .. "Reserved"])
	self:setFlags(args[pre .. "Flags"])
	if args[pre .. "Urg"] and args[pre .. "Urg"] ~= 0 then
		self:setUrg()
	end
	if args[pre .. "Ack"] and args[pre .. "Ack"] ~= 0 then
		self:setAck()
	end
	if args[pre .. "Psh"] and args[pre .. "Psh"] ~= 0 then
		self:setPsh()
	end
	if args[pre .. "Rst"] and args[pre .. "Rst"] ~= 0 then
		self:setRst()
	end
	if args[pre .. "Syn"] and args[pre .. "Syn"] ~= 0 then
		self:setSyn()
	end
	if args[pre .. "Fin"] and args[pre .. "Fin"] ~= 0 then
		self:setFin()
	end
	self:setWindow(args[pre .. "Window"])
	self:setChecksum(args[pre .. "Checksum"])
	self:setUrgentPointer(args[pre .. "UrgentPointer"])
end

--- Retrieve the values of all members.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see tcpHeader:fill
function tcpHeader:get(pre)
	pre = pre or "tcp"

	local args = {}
	args[pre .. "Src"] = self:getSrcPort()
	args[pre .. "Dst"] = self:getDstPort()
	args[pre .. "SeqNumber"] = self:getSeqNumber()
	args[pre .. "AckNumber"] = self:getAckNumber()
	args[pre .. "DataOffset"] = self:getDataOffset()
	args[pre .. "Reserved"] = self:getReserved()
	args[pre .. "Flags"] = self:getFlags()
	args[pre .. "Urg"] = self:getUrg()
	args[pre .. "Ack"] = self:getAck()
	args[pre .. "Psh"] = self:getPsh()
	args[pre .. "Rst"] = self:getRst()
	args[pre .. "Syn"] = self:getSyn()
	args[pre .. "Fin"] = self:getFin()
	args[pre .. "Window"] = self:getWindow()
	args[pre .. "Checksum"] = self:getChecksum()
	args[pre .. "UrgentPointer"] = self:getUrgentPointer()
	
	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function tcpHeader:getString()
	return "TCP " 		.. self:getSrcPortString() 
		.. " > " 	.. self:getDstPortString() 
		.. " seq# " 	.. self:getSeqNumberString()
		.. " ack# " 	.. self:getAckNumberString() 
		.. " offset " 	.. self:getDataOffsetString() 
		.. " reserved " .. self:getReservedString()
		.. " flags " 	.. self:getFlagsString() 
		.. " [" 	.. self:getUrgString() 
		.. "|" 		.. self:getAckString() 
		.. "|" 		.. self:getPshString() 
		.. "|" 		.. self:getRstString() 
		.. "|" 		.. self:getSynString() 
		.. "|" 		.. self:getFinString()
		.."] win " 	.. self:getWindowString() 
		.. " cksum " 	.. self:getChecksumString() 
		.. " urg " 	.. self:getUrgentPointerString() 
end

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function tcpHeader:resolveNextHeader()
	return nil
end

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'tcp'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see tcpHeader:fill
function tcpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end


----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

--- Cast the packet to a Tcp (IP4) packet
pkt.getTcp4Packet = packetCreate("eth", "ip4", "tcp")
--- Cast the packet to a Tcp (IP6) packet
pkt.getTcp6Packet = packetCreate("eth", "ip6", "tcp")
--- Cast the packet to a Tcp packet, either using IP4 (nil/true) or IP6 (false), depending on the passed boolean.
pkt.getTcpPacket = function(self, ip4) 
	ip4 = ip4 == nil or ip4 
	if ip4 then 
		return pkt.getTcp4Packet(self) 
	else 
		return pkt.getTcp6Packet(self) 
	end 
end   

------------------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------------------

ffi.metatype("struct tcp_header", tcpHeader)
