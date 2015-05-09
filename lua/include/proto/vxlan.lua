local ffi = require "ffi"
local pkt = require "packet"

require "headers"

local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local format = string.format

---------------------------------------------------------------------------
--- vxlan constants 
---------------------------------------------------------------------------

local vxlan = {}


---------------------------------------------------------------------------
--- vxlan header
---------------------------------------------------------------------------

local vxlanHeader = {}
vxlanHeader.__index = vxlanHeader

function vxlanHeader:setFlags(int)
	int = int or 8 -- '00001000'
	self.flags = int
end

function vxlanHeader:getFlags()
	return self.flags
end

function vxlanHeader:getFlagsString()
	return format("0x%02x", self:getFlags())
end

function vxlanHeader:setReserved(int)
	int = int or 0
	
	-- X 3 2 1 ->  1 2 3
	self.reserved[0] = rshift(band(int, 0xFF0000), 16)
	self.reserved[1] = rshift(band(int, 0x00FF00), 8)
	self.reserved[2] = band(int, 0x0000FF)
end

function vxlanHeader:getReserved()
	return bor(lshift(self.reserved[0], 16), bor(lshift(self.reserved[1], 8), self.reserved[2]))
end

function vxlanHeader:getReservedString()
	return format("0x%06x", self:getReserved())
end

function vxlanHeader:setVNI(int)
	int = int or 0
	
	-- X 3 2 1 ->  1 2 3
	self.vni[0] = rshift(band(int, 0xFF0000), 16)
	self.vni[1] = rshift(band(int, 0x00FF00), 8)
	self.vni[2] = band(int, 0x0000FF)
end

function vxlanHeader:getVNI()
	return bor(lshift(self.vni[0], 16), bor(lshift(self.vni[1], 8), self.vni[2]))
end

function vxlanHeader:getVNIString()
	return format("0x%06x", self:getVNI())
end

function vxlanHeader:setReserved2(int)
	int = int or 0
	self.reserved2 = int
end

function vxlanHeader:getReserved2()
	return self.reserved2
end

function vxlanHeader:getReserved2String()
	return format("0x%02x", self:getReserved2())
end

--- Set all members of the vxlan header.
-- Per default, all members are set to default values specified in the respective set function.
-- Optional named arguments can be used to set a member to a user-provided value.
-- @param args Table of named arguments. Available arguments: vxlanFlags, vxlanVNI, vxlanReserved, vxlanReserved2
-- @param pre prefix for namedArgs. Default 'vxlan'.
-- @usage fill() -- only default values
-- @usage fill{ vxlanFlags=1 } -- all members are set to default values with the exception of vxlanFlags, ...
function vxlanHeader:fill(args, pre)
	args = args or {}
	pre = pre or "vxlan"
	
	self:setFlags(args[pre .. "Flags"])
	self:setReserved(args[pre .. "Reserved"])
	self:setVNI(args[pre .. "VNI"])
	self:setReserved2(args[pre .. "Reserved2"])
end

--- Retrieve the values of all members.
-- @param pre prefix for namedArgs. Default 'vxlan'.
-- @return Table of named arguments. For a list of arguments see "See also".
-- @see vxlanHeader:fill
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
-- @return Values in string format.
function vxlanHeader:getString()
	return "VXLAN flags " .. self:getFlagsString() 
		.. " res " .. self:getReservedString()
		.. " vni " .. self:getVNIString()
		.. " res " .. self:getReserved2String()
end

function vxlanHeader:resolveNextHeader()
	return nil
end	

function vxlanHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
--- Packets
----------------------------------------------------------------------------------

-- TODO replace eth with 802.1Q (NYI)
pkt.getVxlanPacket = packetCreate("eth", "ip4", "udp", "vxlan", { "eth", "innerEth" })


------------------------------------------------------------------------
--- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct vxlan_header", vxlanHeader)


return vxlan
