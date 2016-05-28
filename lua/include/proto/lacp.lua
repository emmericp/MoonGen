------------------------------------------------------------------------
--- @file lacp.lua
--- @brief Implementation of 802.3ad aka LACP.
--- Utility functions for the lacp_header structs 
--- defined in \ref headers.lua . \n
--- Includes:
--- - LACP constants
--- - LACP header utility
--- - Definition of LACP packets
------------------------------------------------------------------------

-- structs and constants partially copied from Open vSwitch lacp.c (Apache 2.0 license)

local ffi = require "ffi"
local pkt = require "packet"

require "headers"


---------------------------------------------------------------------------
---- lacp constants 
---------------------------------------------------------------------------

--- lacp protocol constants
local lacp = {}

lacp.dstMac = parseMacAddress("01:80:c2:00:00:02")

-- state machine
lacp.STATE_ACT  = 0x01 -- Activity. Active or passive?
lacp.STATE_TIME = 0x02 -- Timeout. Short or long timeout?
lacp.STATE_AGG  = 0x04 -- Aggregation. Is the link is bondable?
lacp.STATE_SYNC = 0x08 -- Synchronization. Is the link in up to date?
lacp.STATE_COL  = 0x10 -- Collecting. Is the link receiving frames?
lacp.STATE_DIST = 0x20 -- Distributing. Is the link sending frames?
lacp.STATE_DEF  = 0x40 -- Defaulted. Using default partner info?
lacp.STATE_EXP  = 0x80 -- Expired. Using expired partner info?

---------------------------------------------------------------------------
---- lacp header
---------------------------------------------------------------------------

--- Module for lacp_address struct (see \ref headers.lua).
local lacpHeader, lacpInfo = {}, {}
lacpHeader.__index = lacpHeader
lacpInfo.__index = lacpInfo

function lacpInfo:setSysPriority(int)
	int = int or 0
	self.sys_priority = hton16(int)
end

function lacpInfo:setKey(int)
	int = int or 0
	self.key = hton16(int)
end

function lacpInfo:setPortPriority(int)
	int = int or 0
	self.port_priority = hton16(int)
end

function lacpInfo:setPortId(int)
	int = int or 0
	self.port_id = hton16(int)
end

--- @param state State as bitfield, see lacp.STATE_ constants
function lacpHeader:setState(state)
	self.state = state
end


function lacpInfo:getSysPriority()
	return ntoh16(self.sys_priority)
end

function lacpInfo:getKey()
	return ntoh16(self.key)
end

function lacpInfo:setPortPriority()
	return ntoh16(self.port_priority)
end

function lacpInfo:setPortId()
	return ntoh16(self.port_id)
end

--- @return State as bitfield, see lacp.STATE_ constants
function lacpHeader:getState(state)
	return self.state
end

--- Set all members of the lacp header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: {Actor|Partner}{SysPriority|SysId|Key|PortPriority|PortId|State}
--- @param pre prefix for namedArgs. Default 'lacp'.
--- @code
--- fill() -- only default values
--- fill{ lacpXYZ=1 } -- all members are set to default values with the exception of lacpXYZ, ...
--- @endcode
function lacpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "lacp"
	-- protocol constants, making these modifiable makes no sense
	-- (just set them yourself outside of fill if you need different values for strange reasons)
	self.subtype = 1
	self.version = 1
	self.actor_type = 1
	self.actor_len = 20
	self.partner_type = 2
	self.partner_len = 20
	self.collector_type = 3
	self.collector_len = 16
	self.collector_delay = 0
	-- z1 - z3: implicitly zeroed
	local actor = self.actorInfo
	actor:setSysPriority(args[pre .. "ActorSysPriority"])
	actor:setKey(args[pre .. "ActorKey"])
	actor:setPortPriority(args[pre .. "ActorPortPriority"])
	actor:setPortId(args[pre .. "ActorPortId"])
	actor:setState(args[pre .. "ActorState"])
	actor.sys_id:set(args[pre .. "ActorSysId"])
	local partner = self.partnerInfo
	partner:setSysPriority(args[pre .. "PartnerSysPriority"])
	partner:setKey(args[pre .. "PartnerKey"])
	partner:setPortPriority(args[pre .. "PartnerPortPriority"])
	partner:setPortId(args[pre .. "PartnerPortId"])
	partner:setState(args[pre .. "PartnerState"])
	partner.sys_id:set(args[pre .. "PartnerSysId"])
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'lacp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see lacpHeader:fill
function lacpHeader:get(pre)
	pre = pre or "lacp"

	local args = {}
	args[pre .. "lacpXYZ"] = self:getXYZ() 

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function lacpHeader:getString()
	return "lacp " .. self:getXYZString()
end

--- Resolve which header comes after this one (in a packet)
--- For instance: in tcp/udp based on the ports
--- This function must exist and is only used when get/dump is executed on 
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'eth', 'ip4', nil)
function lacpHeader:resolveNextHeader()
	return nil
end	

--- Change the default values for namedArguments (for fill/get)
--- This can be used to for instance calculate a length value based on the total packet length
--- See proto/ip4.setDefaultNamedArgs as an example
--- This function must exist and is only used by packet.fill
--- @param pre The prefix used for the namedArgs, e.g. 'lacp'
--- @param namedArgs Table of named arguments (see See more)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see lacpHeader:fill
function lacpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end

----------------------------------------------------------------------------------
---- Packets
----------------------------------------------------------------------------------

--[[ define how a packet with this header looks like
-- e.g. 'ip4' will add a member ip4 of type struct ip4_header to the packet
-- e.g. {'ip4', 'innerIP'} will add a member innerIP of type struct ip4_header to the packet
--]]
--- Cast the packet to a lacp (IP4) packet 
pkt.getlacpPacket = packetCreate('eth', 'ip4', 'lacp')


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct lacp_header", lacpHeader)


return lacp
