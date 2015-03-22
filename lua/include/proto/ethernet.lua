local ffi = require "ffi"

require "utils"
require "headers"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local istype = ffi.istype
local format = string.format


------------------------------------------------------------------------
--- Ethernet constants
------------------------------------------------------------------------

local eth = {}

eth.TYPE_IP = 0x0800
eth.TYPE_ARP = 0x0806
eth.TYPE_IP6 = 0x86dd
eth.TYPE_PTP = 0x88f7

eth.BROADCAST = "ff:ff:ff:ff:ff:ff"

------------------------------------------------------------------------
--- Mac addresses
------------------------------------------------------------------------

local macAddr = {}
macAddr.__index = macAddr
local macAddrType = ffi.typeof("struct mac_address")

--- Retrieve the MAC address.
-- @return Address in 'struct mac_address' format.
function macAddr:get()
	local addr = macAddrType()
	for i = 0, 5 do
		addr.uint8[i] = self.uint8[i]
	end
	return addr
end

--- Set the MAC address.
-- @param addr Address in 'struct mac_address' format.
function macAddr:set(addr)
	for i = 0, 5 do
		self.uint8[i] = addr.uint8[i]
	end
end

--- Set the MAC address.
-- @param mac Address in string format.
function macAddr:setString(mac)
	self:set(parseMacAddress(mac))
end

--- Test equality of two MAC addresses.
-- @param lhs Address in 'struct mac_address' format.
-- @param rhs Address in 'struct mac_address' format.
-- @return true if equal, false otherwise.
function macAddr.__eq(lhs, rhs)
	local isMAC = istype(macAddrType, lhs) and istype(macAddrType, rhs) 
	for i = 0, 5 do
		isMAC = isMAC and lhs.uint8[i] == rhs.uint8[i] 
	end
	return isMAC
end

--- Retrieve the string representation of a MAC address.
-- @return Address in string format.
function macAddr:getString()
	return ("%02x:%02x:%02x:%02x:%02x:%02x"):format(
			self.uint8[0], self.uint8[1], self.uint8[2], 
			self.uint8[3], self.uint8[4], self.uint8[5]
			)
end


----------------------------------------------------------------------------
--- Ethernet header
----------------------------------------------------------------------------

local etherHeader = {}
etherHeader.__index = etherHeader

--- Set the destination MAC address.
-- @param addr Address in 'struct mac_address' format.
function etherHeader:setDst(addr)
	self.dst:set(addr)
end

--- Retrieve the destination MAC address.
-- @return Address in 'struct mac_address' format.
function etherHeader:getDst(addr)
	return self.dst:get()
end

--- Set the source MAC address.
-- @param addr Address in 'struct mac_address' format.
function etherHeader:setSrc(addr)
	self.src:set(addr)
end

--- Retrieve the source MAC address.
-- @return Address in 'struct mac_address' format.
function etherHeader:getSrc(addr)
	return self.src:get()
end

--- Set the destination MAC address.
-- @param str Address in string format.
function etherHeader:setDstString(str)
	self.dst:setString(str)
end

--- Retrieve the destination MAC address.
-- @return Address in string format.
function etherHeader:getDstString()
	return self.dst:getString()
end

--- Set the source MAC address.
-- @param str Address in string format.
function etherHeader:setSrcString(str)
	self.src:setString(str)
end

--- Retrieve the source MAC address.
-- @return Address in string format.
function etherHeader:getSrcString()
	return self.src:getString()
end

--- Set the EtherType.
-- @param int EtherType as 16 bit integer.
function etherHeader:setType(int)
	int = int or eth.TYPE_IP
	self.type = hton16(int)
end

--- Retrieve the EtherType.
-- @return EtherType as 16 bit integer.
function etherHeader:getType()
	return hton16(self.type)
end

--- Retrieve the ether type.
-- @return EtherType as string.
function etherHeader:getTypeString()
	local type = self:getType()
	local cleartext = ""
	
	if type == eth.TYPE_IP then
		cleartext = "(IP4)"
	elseif type == eth.TYPE_IP6 then
		cleartext = "(IP6)"
	elseif type == eth.TYPE_ARP then
		cleartext = "(ARP)"
	else
		cleartext = "(unknown)"
	end

	return format("0x%04x %s", type, cleartext)
end

--- Set all members of the ethernet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: ethSrc, ethDst, ethType
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67", ethType=0x137 } -- default value for ethDst; ethSrc and ethType user-specified
function etherHeader:fill(args)
	args = args or {}

	args.ethSrc = args.ethSrc or "01:02:03:04:05:06"
	args.ethDst = args.ethDst or "07:08:09:0a:0b:0c"
	
	-- addresses can be either a string, a mac_address ctype or a device/queue object
	if type(args.ethSrc) == "string" then
		self:setSrcString(args.ethSrc)
	elseif istype(macAddrType, args.ethSrc) then
		self:setSrc(args.ethSrc)
	elseif type(args.ethSrc) == "table" and args.ethSrc.id then
		self:setSrcString((args.ethSrc.dev or args.ethSrc):getMacString())
	end
	if type(args.ethDst) == "string" then
		self:setDstString(args.ethDst)
	elseif istype(macAddrType, args.ethDst) then
		self:setDst(args.ethDst)
	elseif type(args.ethDst) == "table" and args.ethDst.id then
		self:setDstString((args.ethDst.dev or args.ethDst):getMacString())
	end
	self:setType(args.ethType)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:fill
function etherHeader:get()
	return { ethSrc=self:getSrcString(), ethDst=self:getDstString(), ethType=self:getType() }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function etherHeader:getString()
	return "ETH " .. self:getSrcString() .. " > " .. self:getDstString() .. " type " .. self:getTypeString()
end


--------------------------------------------------------------------------------
--- Ethernet packet
--------------------------------------------------------------------------------

local etherPacket = {}
etherPacket.__index = etherPacket

--- Set all members of the ethernet header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. For a list of available arguments see "See also"
-- @usage fill() -- only default values
-- @usage fill{ ethSrc="12:23:34:45:56:67" } -- all members are set to default values with the exception of ethSrc
-- @see etherHeader:fill
function etherPacket:fill(args)
	args = args or {}

	self.eth:fill(args)
end

--- Retrieve the values of all members.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see etherHeader:get
function etherPacket:get()
	return self.eth:get()
end

--- Print information about the headers and a hex dump of the complete packet.
-- @param bytes Number of bytes to dump.
function etherPacket:dump(bytes)
	dumpPacket(self, bytes, self.eth)
end


----------------------------------------------------------------------------------
--- Metatypes
----------------------------------------------------------------------------------

ffi.metatype("struct mac_address", macAddr)
ffi.metatype("struct ethernet_packet", etherPacket)
ffi.metatype("struct ethernet_header", etherHeader)

return eth
