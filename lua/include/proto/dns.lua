------------------------------------------------------------------------
--- @file dns.lua
--- @brief (dns) utility.
--- Utility functions for the dns_header structs 
--- defined in \ref headers.lua . \n
--- Includes:
--- - dns constants
--- - dns header utility
--- - Definition of dns packets
---
--- Copyright (c) Santiago R.R. <santiago.ruano-rincon@telecom-bretagne.eu>
------------------------------------------------------------------------

--[[
-- TODO: Does this DNS header need a length member?
-- check: - packet.lua: if the header has a length member, adapt packetSetLength; 
--]]

local ffi = require "ffi"
local pkt = require "packet"

local ntoh, hton = ntoh, hton
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
require "headers"

require "math"

---------------------------------------------------------------------------
---- dns constants 
---------------------------------------------------------------------------

--- dns protocol constants
local dns = {}


---------------------------------------------------------------------------
---- dns header
---------------------------------------------------------------------------


--[[ From the RFC 1035, https://www.ietf.org/rfc/rfc1035.txt

The header contains the following fields:

                                    1  1  1  1  1  1
      0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |                      ID                       |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |                    QDCOUNT                    |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |                    ANCOUNT                    |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |                    NSCOUNT                    |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    |                    ARCOUNT                    |
    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+

where:

ID              A 16 bit identifier assigned by the program that
                generates any kind of query.  This identifier is copied
                the corresponding reply and can be used by the requester
                to match up replies to outstanding queries.

QR              A one bit field that specifies whether this message is a
                query (0), or a response (1).

OPCODE          A four bit field that specifies kind of query in this
                message.  This value is set by the originator of a query
                and copied into the response.  The values are:

                0               a standard query (QUERY)

                1               an inverse query (IQUERY)

                2               a server status request (STATUS)

                3-15            reserved for future use

AA              Authoritative Answer - this bit is valid in responses,
                and specifies that the responding name server is an
                authority for the domain name in question section.

                Note that the contents of the answer section may have
                multiple owner names because of aliases.  The AA bit
                corresponds to the name which matches the query name, or
                the first owner name in the answer section.

TC              TrunCation - specifies that this message was truncated
                due to length greater than that permitted on the
                transmission channel.

RD              Recursion Desired - this bit may be set in a query and
                is copied into the response.  If RD is set, it directs
                the name server to pursue the query recursively.
                Recursive query support is optional.

RA              Recursion Available - this be is set or cleared in a
                response, and denotes whether recursive query support is
                available in the name server.

Z               Reserved for future use.  Must be zero in all queries
                and responses.

RCODE           Response code - this 4 bit field is set as part of
                responses.  The values have the following
                interpretation:

                0               No error condition

                1               Format error - The name server was
                                unable to interpret the query.

                2               Server failure - The name server was
                                unable to process this query due to a
                                problem with the name server.

                3               Name Error - Meaningful only for
                                responses from an authoritative name
                                server, this code signifies that the
                                domain name referenced in the query does
                                not exist.

                4               Not Implemented - The name server does
                                not support the requested kind of query.

                5               Refused - The name server refuses to
                                perform the specified operation for
                                policy reasons.  For example, a name
                                server may not wish to provide the
                                information to the particular requester,
                                or a name server may not wish to perform
                                a particular operation (e.g., zone
                                transfer) for particular data.

                6-15            Reserved for future use.

QDCOUNT         an unsigned 16 bit integer specifying the number of
                entries in the question section.

ANCOUNT         an unsigned 16 bit integer specifying the number of
                resource records in the answer section.

NSCOUNT         an unsigned 16 bit integer specifying the number of name
                server resource records in the authority records
                section.

ARCOUNT         an unsigned 16 bit integer specifying the number of
                resource records in the additional records section.
]]--

local dnsHeader = {}
dnsHeader.__index = dnsHeader

--- Set the query id.
--- @param int Id of the dns header as A bit integer.
function dnsHeader:setId(int)
	int = int or math.random(10000,65335)
	self.id = hton16(int)
end

--- Retrieve the id.
--- @return the qurey id as a bit integer.
function dnsHeader:getId()
	return hton16(self.id)
end

--- Retrieve the id as string.
--- @return the qurey id as string.
function dnsHeader:getIdString()
	return self:getId()
end

--- Set Question/Response bit: 
--- 0 Question, 1 = Answer.
function dnsHeader:setQR()
	self.hdrflags = bor(self.hdrflags, 0x8000)
end

--- Unset Question/Response bit: 
--- 0 Question, 1 = Answer.
function dnsHeader:unsetQR()
	self.hdrflags = band(self.hdrflags, 0x7FFF)
end

--- Retrieve the QR.
--- @return QR as 1 bit integer.
function dnsHeader:getQR()
	return rshift(band(self.hdrflags, 0x8000), 1)
end

--- Retrieve the QR as string.
--- @return QR as string.
function dnsHeader:getQRString()
	if self:getQR() == 1 then
		return "R"
	else
		return "Q"
	end
end

--- Set the OPCode: Kind of query.
--- 0 a standard query (QUERY)
--- 1 an inverse query (IQUERY)
--- 2 a server status request (STATUS)
--- 3-15 reserved for future use
--- @param int OPCode of the dns header as A bit integer.
function dnsHeader:setOPCode(int)
	int = int or 0
	if int >= 0 and int <= 15 then
		opcode = int

		--- X0000XXX XXXXXXXX
		opcode = lshift(opcode,11)
		self.hdrflags = bor(self.hdrflags, opcode)
	end
	-- TODO: handle invalid args
end

--- Retrieve the OPCode.
--- @return OPCode as A bit integer.
function dnsHeader:getOPCode()
	res = rshift(band(self.hdrflags, 0x7800), 11)
	return res
end

--- Retrieve the OPCode as string.
--- @return OPCode as string.
function dnsHeader:getOPCodeString()
	opcode = self.getOPCode
	if opcode == 0 then
		return "StandardQuery"
	elseif opcode == 1 then
		return "InverseQuery"
	elseif opcode == 2 then
		return "ServerStatus"
	else
		return -1
	end
end

--- Set Authoritative answer bit: 
function dnsHeader:setAA()
	self.hdrflags = bor(self.hdrflags, 0x0400)
end

--- Unset Authoritative answer bit: 
function dnsHeader:unsetAA()
	self.hdrflags = band(self.hdrflags, 0xFBFF)
end

--- Retrieve the AA.
--- @return AA as 1 bit integer.
function dnsHeader:getAA()
	return rshift(band(self.hdrflags, 0x0400), 1)
end

--- Retrieve the AA as string.
--- @return AA as string.
function dnsHeader:getAAString()
	if self:getAA() == 1 then
		return "Authoritative answer"
	else
		return "Non-Authoritative answer"
	end
end

--- Set Truncated message
function dnsHeader:setTC()
	self.hdrflags = bor(self.hdrflags, 0x0200)
end

--- Unset Truncated message bit: 
function dnsHeader:unsetTC()
	self.hdrflags = band(self.hdrflags, 0xFDFF)
end

--- Retrieve the TA.
--- @return TA as 1 bit integer.
function dnsHeader:getTC()
	return rshift(band(self.hdrflags, 0x0200), 1)
end

--- Retrieve the TA as string.
--- @return TA as string.
function dnsHeader:getTCString()
	if self:getTC() == 1 then
		return "Truncated message"
	else
		return "Non-truncated message"
	end
end

--- Set Recursion Desired
function dnsHeader:setRD()
	self.hdrflags = bor(self.hdrflags, 0x0100)
end

--- Unset Recursion Desired bit: 
function dnsHeader:unsetRD()
	self.hdrflags = band(self.hdrflags, 0xFEFF)
end

--- Retrieve the RD.
--- @return RD as 1 bit integer.
function dnsHeader:getRD()
	return rshift(band(self.hdrflags, 0x0100), 1)
end

--- Retrieve the RD as string.
--- @return RD as string.
function dnsHeader:getRDString()
	if self:getRD() == 1 then
		return "Recursion desired"
	else
		return "Recursion undesired"
	end
end

--- Set Recursion Available
function dnsHeader:setRA()
	self.hdrflags = bor(self.hdrflags, 0x0080)
end

--- Unset Recursion Available bit: 
function dnsHeader:unsetRA()
	self.hdrflags = band(self.hdrflags, 0xFF7F)
end

--- Retrieve the RA.
--- @return RA as 1 bit integer.
function dnsHeader:getRA()
	return rshift(band(self.hdrflags, 0x0080), 1)
end

--- Retrieve the RA as string.
--- @return RA as string.
function dnsHeader:getRAString()
	if self:getRA() == 1 then
		return "Recursion available"
	else
		return "Recursion unavailable"
	end
end

--- Set the 4-bit Response code
--- 0 No error condition
--- 1 Format error
--- 2 Server failure
--- 3 Name Error
--- 4 Not Implemented
--- 5 Refused
--- 6-15 Reserved for future use.
--- @param int RCode of the dns header as A bit integer.
function dnsHeader:setRCode(int)
	int = int or 0
	if int >= 0 and int <= 15 then
		rcode = int

		--- XXXXXXXX XXXX0000
		opcode = lshift(opcode,11)
		self.hdrflags = bor(self.hdrflags, opcode)
	end
	-- TODO: handle invalid args
end

--- Retrieve the RCode.
--- @return RCode as A bit integer.
function dnsHeader:getRCode()
	res = band(self.hdrflags, 0x000F)
	return res
end

--- Retrieve the RCode as string.
--- @return RCode as string.
function dnsHeader:getRCodeString()
	rcode = self.getRCode
	if rcode == 0 then
		return "NOERROR"
	elseif rcode == 1 then
		return "FORMERR"
	elseif rcode == 2 then
		return "SERVFAIL"
	elseif rcode == 3 then
		return "NXDOMAIN"
	elseif rcode == 4 then
		return "NOTIMP"
	elseif rcode == 5 then
		return "REFUSED"
	else
		return -1
	end
end


--- Set the QDCount.
--- @param int QDCount of the dns header as A bit integer.
function dnsHeader:setQDCount(int)
	int = int or 0
	self.qdcount = hton16(int)
end

--- Retrieve the QDCount.
--- @return QDCount as A bit integer.
function dnsHeader:getQDCount()
	return hton16(self.qdcount)
end

--- Retrieve the QDCount as string.
--- @return QDCount as string.
function dnsHeader:getQDCountString()
	return self:getQDCount()
end

--- Set the ANCount.
--- @param int ANCount of the dns header as A bit integer.
function dnsHeader:setANCount(int)
	int = int or 0
	self.ancount = hton16(int)
end

--- Retrieve the ANCount.
--- @return ANCount as A bit integer.
function dnsHeader:getANCount()
	return hton16(self.ancount)
end

--- Retrieve the ANCount as string.
--- @return ANCount as string.
function dnsHeader:getANCountString()
	return self:getANCount()
end


--- Set the NSCount.
--- @param int NSCount of the dns header as A bit integer.
function dnsHeader:setNSCount(int)
	int = int or 0
	self.nscount = hton16(int)
end

--- Retrieve the NSCount.
--- @return NSCount as A bit integer.
function dnsHeader:getNSCount()
	return hton16(self.nscount)
end

--- Retrieve the NSCount as string.
--- @return NSCount as string.
function dnsHeader:getNSCountString()
	return self:getNSCount()
end


--- Set the ARCount.
--- @param int ARCount of the dns header as A bit integer.
function dnsHeader:setARCount(int)
	int = int or 0
	self.arcount = hton16(int)
end

--- Retrieve the ARCount.
--- @return ARCount as A bit integer.
function dnsHeader:getARCount()
	return hton16(self.arcount)
end

--- Retrieve the ARCount as string.
--- @return ARCount as string.
function dnsHeader:getARCountString()
	return self:getARCount()
end

--- Set the Data for the remaining sections in the DNS Message.
--function dnsHeader:setMessageContent(...)
function dnsHeader:setMessageContent(...)
	local args = {...}
	if type(args[1]) == "table" then
		self.body = args[1]
	elseif type(args[1]) == "function" then
		func = args[1]
		self.body = func()
	end
end

--- Retrieve the QueryBody.
--- @return QueryBody as bit integer array?.
function dnsHeader:getMessageContent()
	-- TODO implement!
	return self.body 
end

--- Retrieve the QueryBody as string.
--- @return QueryBody as string.
function dnsHeader:getMessageContentString()
	return self:getMessageContent()
end


--- Set all members of the dns header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: dnsXYZ
--- @param pre prefix for namedArgs. Default 'dns'.
--- @code
--- fill() -- only default values
--- fill{ dnsXYZ=1 } -- all members are set to default values with the exception of dnsXYZ, ...
--- @endcode
function dnsHeader:fill(args, pre)
	args = args or {}
	pre = pre or "dns"

	self:setId(args[pre .. "Id"])
	if args[pre .. "Resp"] and args[pre .. "Resp"] ~= 0 then
		self:setQR()
	end
	self:setOPCode(args[pre .. "QueryType"])
	if args[pre .. "AuthAnswer"] and args[pre .. "AuthAnswer"] ~= 0 then
		self:setAA()
	end
	if args[pre .. "Truncated"] and args[pre .. "Truncated"] ~= 0 then
		self:setTC()
	end
	if args[pre .. "RecDesired"] and args[pre .. "RecDesired"] ~= 0 then
		self:setRD()
	end
	if args[pre .. "RecAvailable"] and args[pre .. "RecAvailable"] ~= 0 then
		self:setRA()
	end
	self:setRCode(args[pre .. "RCode"])
	self:setQDCount(args[pre .. "QDCount"])
	self:setANCount(args[pre .. "ANCount"])
	self:setNSCount(args[pre .. "NSCount"])
	self:setARCount(args[pre .. "ARCount"])
	self:setMessageContent(args[pre .."MessageContent"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'dns'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see dnsHeader:fill
function dnsHeader:get(pre)
	pre = pre or "dns"

	args[pre .. "Id"] = self:getId()
	args[pre .. "Resp"] = self:getQR()
	args[pre .. "QueryType"] = self:getOPCode()
	args[pre .. "AuthoritativeAnswer"] = self:getAA()
	args[pre .. "Truncation"] = self:getTC()
	args[pre .. "RecursionDesired"] = self:getRD()
	args[pre .. "RecursionAvailable"] = self:getRA()
	args[pre .. "RCode"] = self:getRCode()
	args[pre .. "QDCount"] = self:getQDCount()
	args[pre .. "ANCount"] = self:getANCount()
	args[pre .. "NSCount"] = self:getNSCount()
	args[pre .. "ARCount"] = self:getARCount()
	args[pre .. "MessageContent"] = self:getMessageContent()

	--[[
	-- TODO: it would be nice to implenet function to directly get
	-- content  something like:
	args[pre .. "QuerySection" ] = self:getQuerySection()
	args[pre .. "AnswerSection" ] = self:getAnswerSection()
	args[pre .. "AuthoritativeNSSection" ] = self:getNSSection()
	args[pre .. "AdditionalRRSection" ] = self:getARSection()
	]]--
	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function dnsHeader:getString()
	return "DNS "  
		.. "Transation ID: " .. self:getIdString()
		.. "Response/Query: " .. self:getQRString()
		.. "Kind of query: " .. self:getOPCodeString()
		.. "Authoritative Answer: " .. self:getAAString()
		.. "Truncated message: " .. self:getTCString()
		.. "Recursion desired: " .. self:getRDString()
		.. "Recursion available: " .. self:getRAString()
		.. "Response Code: " .. self:getRCodeString()
		.. "QDCount: " .. self:getQDCountString()
		.. "ANCount: " .. self:getANCountString()
		.. "NSCount: " .. self:getNSCountString()
		.. "ARCount: " .. self:getARCountString()
		.. "MessageContent: " .. self:getMessageContentString()
end

--- Resolve which header comes after this one (in a packet)
--- For instance: in tcp/udp based on the ports
--- This function must exist and is only used when get/dump is executed on 
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'eth', 'ip4', nil)
function dnsHeader:resolveNextHeader()
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
--- This can be used to for instance calculate a length value based on the total packet length
--- See proto/ip4.setDefaultNamedArgs as an example
--- This function must exist and is only used by packet.fill
--- @param pre The prefix used for the namedArgs, e.g. 'dns'
--- @param namedArgs Table of named arguments (see See more)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see dnsHeader:fill
function dnsHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	--[[ Example from upd.lua ]]--
	-- set length
	if not namedArgs[pre .. "Length"] and namedArgs["pktLength"] then
		namedArgs[pre .. "Length"] = namedArgs["pktLength"] - accumulatedLength
	end

	return namedArgs

end

----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

--[[ define how a packet with this header looks like
-- e.g. 'ip4' will add a member ip4 of type struct ip4_header to the packet
-- e.g. {'ip4', 'innerIP'} will add a member innerIP of type struct ip4_header to the packet
--]]
--- Cast the packet to a DNS (IP4) packet 
pkt.getDns4Packet = packetCreate('eth', 'ip4', 'udp', 'dns')

--- Cast the packet to a DNS (IP6) packet
pkt.getDns6Packet = packetCreate('eth', 'ip6', 'udp', 'dns')

--- Cast the packet to a DNS (IPv4) packet, either using IP4 (nil/true) or IP6 (false), depending on the passed boolean.
pkt.getDnsPacket = function(self, ip4) 
	ip4 = ip4 == nil or ip4 
	if ip4 then 
		return pkt.getDns4Packet(self) 
	else 
		return pkt.getDns6Packet(self) 
	end 
end

------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct dns_header", dnsHeader)

return dns
