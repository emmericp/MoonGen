local ffi = require "ffi"

require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local eth = require "ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bswap = bswap
local bswap16 = bswap16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype

local arp = {}

--- ARP constants (c.f. http://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml)
-- hrd
arp.HW_ADDR_TYPE_ETHERNET = 1

-- pro (for ethernet based protocols uses ether type numbers)
arp.PROTO_ADDR_TYPE_IP = 0x0800

-- op
arp.OP_REQUEST = 1
arp.OP_REPLY = 2


--- ARP header
local arpHeader = {}
arpHeader.__index = arpHeader

--- Set the hardware address type.
-- @param int Type as 16 bit integer.
function arpHeader:setHWAddressType(int) -- TODO HW or Hardware
	int = int or arp.HW_ADDR_TYPE_ETHERNET
	self.hrd = hton16(int)
end

--- Retrieve the hardware address type.
-- @return Type as 16 bit integer.
function arpHeader:getHWAddressType()
	return hton16(self.hrd)
end

--- Retrieve the hardware address type.
-- @return Type in string format.
function arpHeader:getHWAddressTypeString()
	return self:getHWAddressType() -- TODO
end
	
function arpHeader:setProtoAddressType(int) -- TODO proto or protocol
	int = int or arp.PROTO_ADDR_TYPE_IP
	self.pro = hton16(int)
end

function arpHeader:getProtoAddressType()
	return hton16(self.pro)
end

function arpHeader:getProtoAddressTypeString()
	return self:getProtoAddressType() -- TODO
end

function arpHeader:setHWAddressLength(int) -- TODO
	int = int or 6
	self.hln = int
end

function arpHeader:getHWAddressLength()
	return self.hln
end

function arpHeader:getHWAddressLengthString()
	return self:getHWAddressLength()
end

function arpHeader:setProtoAddressLength(int) -- TODO
	int = int or 4
	self.pln = int
end

function arpHeader:getProtoAddressLength()
	return self.pln
end

function arpHeader:getProtoAddressLengthString()
	return self:getProtoAddressLength()
end

function arpHeader:setOperation(int)
	int = int or arp.OP_REQUEST
	self.op = hton16(int)
end

function arpHeader:getOperation()
	return hton16(self.op)
end

function arpHeader:getOperationString()
	return self:getOperation() -- TODO
end

function arpHeader:setHWSrc(addr) --TODO
	self.sha:set(addr)
end

function arpHeader:getHWSrc()
	return self.sha:get()
end

function arpHeader:setHWSrcString(addr) --TODO
	self.sha:setString(addr)
end

function arpHeader:getHWSrcString()
	return self.sha:getString()
end

function arpHeader:setHWDst(addr) --TODO
	self.tha:set(addr)
end

function arpHeader:getHWDst()
	return self.tha:get()
end

function arpHeader:setHWDstString(addr) --TODO
	self.tha:setString(addr)
end

function arpHeader:getHWDstString()
	return self.tha:getString()
end

function arpHeader:setProtoSrc(addr) --TODO
	self.spa:set(addr)
end

function arpHeader:getProtoSrc()
	return self.spa:get()
end

function arpHeader:setProtoSrcString(addr) --TODO
	self.spa:setString(addr)
end

function arpHeader:getProtoSrcString()
	return self.spa:getString()
end

function arpHeader:setProtoDst(addr) --TODO
	self.tpa:set(addr)
end

function arpHeader:getProtoDst()
	return self.tpa:get()
end

function arpHeader:setProtoDstString(addr) --TODO
	self.tpa:setString(addr)
end

function arpHeader:getProtoDstString()
	return self.tpa:getString()
end

function arpHeader:fill(args)
	args = args or {}
	
	self:setHWAddressType(args.arpHWAddressType)
	self:setProtoAddressType(args.arpProtoAddressType)
	self:setHWAddressLength(args.arpHWAddressLength)
	self:setProtoAddressLength(args.arpProtoAddressLength)
	self:setOperation(args.arpOperation)

	args.arpHWSrc = args.arpHWSrc or "01:02:03:04:05:06"
	args.arpHWDst = args.arpHWDst or "07:08:09:0a:0b:0c"
	args.arpProtoSrc = args.arpProtoSrc or "0.1.2.3"
	args.arpProtoDst = args.arpProtoDst or "4.5.6.7"
	
	-- if for some reason the address is in 'struct mac_address'/'union ipv4_address' format, cope with it
	if type(args.arpHWSrc) == "string" then
		self:setHWSrcString(args.arpHWSrc)
	else
		self:setHWSrc(args.arpHWSrc)
	end
	if type(args.arpHWDst) == "string" then
		self:setHWDstString(args.arpHWDst)
	else
		self:setHWDst(args.arpHWDst)
	end
	
	if type(args.arpProtoSrc) == "string" then
		self:setProtoSrcString(args.arpProtoSrc)
	else
		self:setProtoSrc(args.arpProtoSrc)
	end
	if type(args.arpProtoDst) == "string" then
		self:setProtoDstString(args.arpProtoDst)
	else
		self:setProtoDst(args.arpProtoDst)
	end
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see arpHeader:fill
function arpHeader:get()
	return { }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function arpHeader:getString()
	return "ARP HRD " .. self:getHWAddressTypeString() .. " PRO " .. self:getProtoAddressTypeString() .. " HLN " .. self:getHWAddressLengthString() 
			.. " PLN " .. self:getProtoAddressLength(String) .. " OP " .. self:getOperationString() .. " " .. self:getHWSrcString() .. " > " 
			.. self:getHWDstString() .. " " .. self:getProtoSrcString() .. " > " .. self:getProtoDstString() .. " "
end

--- Layer 2 packet
local arpPacketType = ffi.typeof("struct arp_packet*")
local arpPacket = {}
arpPacket.__index = arpPacket

--- Set all members of the arpnet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67" } -- all members are set to default values with the exception of ethSrc
-- @see ethernet.etherHeader:fill
-- @see arpHeader:fill
function arpPacket:fill(args)
	args = args or {}

	args.ethType = eth.TYPE_ARP

	self.eth:fill(args)
	self.arp:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see arpHeader:get
function arpPacket:get()
	return mergeTables(self.eth:get(), self.arp:get())
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function arpPacket:dump(bytes)
	str = getTimeMicros() .. self.eth:getString() .. self.arp:getString()
	printLength(str, 60)
	dumpHex(self, bytes)
end

ffi.metatype("struct arp_packet", arpPacket)
ffi.metatype("struct arp_header", arpHeader)

return arp
