------------------------------------------------------------------------
--- @file vxlan.lua
--- @brief VXLAN utility.
--- Utility functions for the vxlan_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - VXLAN constants
--- - VXLAN header utility
--- - Definition of VXLAN packets
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"

require "headers"

local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local format = string.format

---------------------------------------------------------------------------
---- vxlan constants 
---------------------------------------------------------------------------

local vxlan = {}


---------------------------------------------------------------------------
---- vxlan header
---------------------------------------------------------------------------

--- Module for vxlan_header struct (see \ref headers.lua).
local vxlanHeader = {}
vxlanHeader.__index = vxlanHeader

--- Set the flags.
--- @param int VXLAN header flags as 8 bit integer.
function vxlanHeader:setFlags(int)
	int = int or 8 -- '00001000'
	self.flags = int
end

--- Retrieve the flags.
--- @return Flags as 8 bit integer.
function vxlanHeader:getFlags()
	return self.flags
end

--- Retrieve the flags.
--- @return Flags as string.
function vxlanHeader:getFlagsString()
	return format("0x%02x", self:getFlags())
end

--- Set the first reserved field.
--- @param int VXLAN header first reserved field as 24 bit integer.
function vxlanHeader:setReserved(int)
	int = int or 0
	
	-- X 3 2 1 ->  1 2 3
	self.reserved[0] = rshift(band(int, 0xFF0000), 16)
	self.reserved[1] = rshift(band(int, 0x00FF00), 8)
	self.reserved[2] = band(int, 0x0000FF)
end

--- Retrieve the first reserved field.
--- @return First reserved field as 24 bit integer.
function vxlanHeader:getReserved()
	return bor(lshift(self.reserved[0], 16), bor(lshift(self.reserved[1], 8), self.reserved[2]))
end

--- Retrieve the first reserved field.
--- @return First reserved field as string.
function vxlanHeader:getReservedString()
	return format("0x%06x", self:getReserved())
end

--- Set the VXLAN network identifier (VNI).
--- @param int VXLAN header VNI as 24 bit integer.
function vxlanHeader:setVNI(int)
	int = int or 0
	
	-- X 3 2 1 ->  1 2 3
	self.vni[0] = rshift(band(int, 0xFF0000), 16)
	self.vni[1] = rshift(band(int, 0x00FF00), 8)
	self.vni[2] = band(int, 0x0000FF)
end

--- Retrieve the VXLAN network identifier (VNI).
--- @return VNI as 24 bit integer.
function vxlanHeader:getVNI()
	return bor(lshift(self.vni[0], 16), bor(lshift(self.vni[1], 8), self.vni[2]))
end

--- Retrieve the VXLAN network identifier (VNI).
--- @return VNI as string.
function vxlanHeader:getVNIString()
	return format("0x%06x", self:getVNI())
end

--- Set the second reserved field.
--- @param int VXLAN header second reserved field as 8 bit integer.
function vxlanHeader:setReserved2(int)
	int = int or 0
	self.reserved2 = int
end

--- Retrieve the second reserved field.
--- @return Second reserved field as 8 bit integer.
function vxlanHeader:getReserved2()
	return self.reserved2
end

--- Retrieve the second reserved field.
--- @return Second reserved field as string.
function vxlanHeader:getReserved2String()
	return format("0x%02x", self:getReserved2())
end

--- Set all members of the ip header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: Flags, Reserved, VNI, Reserved2
--- @param pre prefix for namedArgs. Default 'vxlan'.
--- @code
--- fill() --- only default values
--- fill{ vxlanFlags=1 } --- all members are set to default values with the exception of vxlanFlags
--- @endcode
function vxlanHeader:fill(args, pre)
	args = args or {}
	pre = pre or "vxlan"
	
	self:setFlags(args[pre .. "Flags"])
	self:setReserved(args[pre .. "Reserved"])
	self:setVNI(args[pre .. "VNI"])
	self:setReserved2(args[pre .. "Reserved2"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'vxlan'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see vxlanHeader:fill
function vxlanHeader:get(pre)
	pre = pre or "vxlan"

	local args = {}
	args[pre .. "Flags"] = self:getFlags() 
	args[pre .. "Reserved"] = self:getReserved() 
	args[pre .. "VNI"] = self:getVNI() 
	args[pre .. "Reserved2"] = self:getReserved2() 

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function vxlanHeader:getString()
	return "VXLAN flags " .. self:getFlagsString() 
		.. " res " .. self:getReservedString()
		.. " vni " .. self:getVNIString()
		.. " res " .. self:getReserved2String()
end

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function vxlanHeader:resolveNextHeader()
	return 'eth'
end	

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'ip4'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see ip4Header:fill
function vxlanHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

pkt.getVxlanPacket = packetCreate("eth", "ip4", "udp", "vxlan", { "eth", "innerEth" })
-- the raw version (only the encapsulating headers, everything else is payload)
pkt.getVxlanEncapsulationPacket = packetCreate("eth", "ip4", "udp", "vxlan")


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct vxlan_header", vxlanHeader)


return vxlan
