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

local ffi    = require "ffi"
local pkt    = require "packet"
local dpdk   = require "dpdk"
local memory = require "memory"
local filter = require "filter"
local ns     = require "namespaces"
local eth    = require "proto.ethernet"

require "headers"


---------------------------------------------------------------------------
---- lacp constants 
---------------------------------------------------------------------------

--- lacp protocol constants
local lacp = {}

lacp.PKT_SIZE = 124
lacp.DST_MAC  = parseMacAddress("01:80:c2:00:00:02")

-- states
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

function lacpInfo.__eq(lhs, rhs)
	return  lhs:equalsIgnoreState(rhs)
		and lhs.state == rhs.state
end

function lacpInfo.equalsIgnoreState(lhs, rhs)
	return  lhs.sys_priority == rhs.sys_priority
		and lhs.sys_id == rhs.sys_id
		and lhs.key == rhs.key
		and lhs.port_priority == rhs.port_priority
		and lhs.port_id == rhs.port_id
end

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
function lacpInfo:setState(state)
	self.state = state or 0
end


function lacpInfo:getSysPriority()
	return ntoh16(self.sys_priority)
end

function lacpInfo:getKey()
	return ntoh16(self.key)
end

function lacpInfo:getPortPriority()
	return ntoh16(self.port_priority)
end

function lacpInfo:getPortId()
	return ntoh16(self.port_id)
end

--- @return State as bitfield, see lacp.STATE_ constants
function lacpInfo:getState()
	return self.state
end

-- @return State as string
function lacpInfo:getStateString()
	local state = self.state
	local s = "["
	if bit.band(state, lacp.STATE_ACT) ~= 0 then
		s = s .. "Activity, "
	end
	if bit.band(state, lacp.STATE_TIME) ~= 0 then
		s = s .. "Timeout, "
	end
	if bit.band(state, lacp.STATE_AGG) ~= 0 then
		s = s .. "Aggregation, "
	end
	if bit.band(state, lacp.STATE_SYNC) ~= 0 then
		s = s .. "Synchronization, "
	end
	if bit.band(state, lacp.STATE_COL) ~= 0 then
		s = s .. "Collecting, "
	end
	if bit.band(state, lacp.STATE_DIST) ~= 0 then
		s = s .. "Distributing, "
	end
	if bit.band(state, lacp.STATE_DEF) ~= 0 then
		s = s .. "Defaulted, "
	end
	if bit.band(state, lacp.STATE_EXP) ~= 0 then
		s = s .. "Expired, "
	end
	if s:sub(#s - 1) == ", " then
		s = s:sub(1, #s - 2)
	end
	return s .. "]"
end

function lacpInfo:getString()
	return ("System %s, System Priority %d, Key %d, Port %d, Port Priority %d, %s"):format(
		self.sys_id:getString(), self:getSysPriority(), self:getKey(), self:getPortId(), self:getPortPriority(), self:getStateString()
	)
end

--- Check whether a LACPDU is well-formed
function lacpHeader:validate()
	return  self.subtype == 1
		and self.version == 1
		and self.actor_type == 1
		and self.actor_len == 20
		and self.partner_type == 2
		and self.partner_len == 20
		and self.collector_type == 3
		and self.collector_len == 16
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
	local actor = self.actor
	actor:setSysPriority(args[pre .. "ActorSysPriority"])
	actor:setKey(args[pre .. "ActorKey"])
	actor:setPortPriority(args[pre .. "ActorPortPriority"])
	actor:setPortId(args[pre .. "ActorPortId"])
	actor:setState(args[pre .. "ActorState"])
	actor.sys_id:setString(args[pre .. "ActorSysId"] or "00:00:00:00:00:00")
	local partner = self.partner
	partner:setSysPriority(args[pre .. "PartnerSysPriority"])
	partner:setKey(args[pre .. "PartnerKey"])
	partner:setPortPriority(args[pre .. "PartnerPortPriority"])
	partner:setPortId(args[pre .. "PartnerPortId"])
	partner:setState(args[pre .. "PartnerState"])
	partner.sys_id:setString(args[pre .. "PartnerSysId"] or "00:00:00:00:00:00")
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'lacp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see lacpHeader:fill
function lacpHeader:get(pre)
	pre = pre or "lacp"
	error("NYI") -- I'm lazy
end

--- Retrieve the values of all members.
--- @return Values in string format.
function lacpHeader:getString()
	if self.subtype ~= 1 or self.version ~= 1 then
		return "Unknown 0x8809 protocol: Type " .. self.subtype .. " Version " .. self.version
	end
	if not self:validate() then
		return "Could not parse payload"
	end
	return "  Actor Information\n"
		.. "    " .. self.actor:getString()
		.. "\n  Partner Information\n"
		.. "    " .. self.partner:getString()
		.. "\n  Collector Information\n"
		.. "    Max Delay " .. ntoh16(self.collector_delay)
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

--- Cast the packet to a lacp packet 
pkt.getLacpPacket = packetCreate('eth', 'lacp')


------------------------------------------------------------------------
---- Metatypes
------------------------------------------------------------------------

ffi.metatype("struct lacp_info", lacpInfo)
ffi.metatype("struct lacp_header", lacpHeader)


------------------------------------------------------------------------
---- LACP Handler Task
------------------------------------------------------------------------

lacp.lacpTask = "__MG_LACP_TASK"

local LACP_TIMEOUT = 30

local status = ns:get()

function lacp:waitForLink(name, minLinks)
	if self ~= lacp then
		return lacp:waitForLink(self, name)
	end
	if not status[name] then
		dpdk.sleepMillisIdle(100)
	end
	if not status[name] then
		-- yes, this is technically speaking a race condition if the other thread takes >= 100ms to startup...
		printf("Port channel %s does not exist", name)
	end
	minLinks = minLinks or status[name].numPorts
	printf("Waiting for at least %d ports on LACP channel %s to come up...", minLinks, name)
	local current = 0
	while true do
		local up = status[name].up
		if up ~= current then
			printf("%d port%s up", up, up > 1 and "s" or "")
			current = up
			if up >= minLinks then
				break
			end
		end
		dpdk.sleepMillisIdle(100)
	end
end

function lacp:getMac(name)
	if self ~= lacp then
		return lacp:getMac(self)
	end
	return status[name].mac
end

-- TODO: support multiple channels (e.g. by passing multiple arguments)
-- this is only a very simplistic implementation of 802.3ad and lacks some features
-- (for example, it does not check whether the IDs on all links match and the rate is hardcoded)
-- use the DPDK implementation if you need something that handles all cases
-- 
-- I actually didn't read the spec, so this may be completely wrong.
-- tested against an Arista 7060CX MLAG LACP running EOS 4.15.3FX
local function lacpTask(channel)
	local ports = channel.ports
	local lacpMac = ports[1].tx.dev:getMacString()
	local mem = memory.createMemPool(function(buf)
		buf:getLacpPacket():fill{
			lacpActorSysId = lacpMac,
			lacpActorSysPriority = 0x7FFF,
			lacpActorPortPriority = 0x7FFF
		}
	end)
	local bufs = memory.bufArray(1)
	local txBufs = mem:bufArray(1)
	for i, port in ipairs(ports) do
		port.rx.dev:l2Filter(eth.TYPE_LACP, port.rx)
		-- receive state machine
		port.rxState = "EXPIRED"
		port.rxStateTimeout = 0
		port.partnerInfo = ffi.new("struct lacp_info")
		port.actorInfo = ffi.new("struct lacp_info")
		port.stateFlags = bit.bor(lacp.STATE_ACT, lacp.STATE_AGG, lacp.STATE_DEF, lacp.STATE_EXP)
	end
	status[channel.name] = { up = 0, numPorts = #ports, mac = lacpMac }
	local lastUpdate = 0
	while dpdk.running() do
		for i, port in ipairs(ports) do
			-- receive
			local rx = port.rx:tryRecvIdle(bufs, 100)
			for i = 1, rx do
				local pkt = bufs[1]:getLacpPacket()
				if pkt.lacp:validate() then
					port.rxState = "CURRENT"
					port.rxStateTimeout = getMonotonicTime() + LACP_TIMEOUT
					ffi.copy(port.partnerInfo, pkt.lacp.actor, ffi.sizeof("struct lacp_info"))
					--print("Received")
					--bufs[1]:dump()
					if port.actorInfo:equalsIgnoreState(pkt.lacp.partner) then
						port.stateFlags = bit.bor(port.stateFlags, lacp.STATE_SYNC)
						port.stateFlags = bit.band(port.stateFlags, bit.bnot(lacp.STATE_DEF))
						port.stateFlags = bit.bor(port.stateFlags, lacp.STATE_COL)
					end
					local down = false
					if bit.band(pkt.lacp.actor.state, lacp.STATE_COL) ~= 0 then
						port.stateFlags = bit.bor(port.stateFlags, lacp.STATE_DIST)
					else
						port.stateFlags = bit.band(port.stateFlags, bit.bnot(lacp.STATE_DIST))
						down = true
					end
					if bit.band(pkt.lacp.actor.state, lacp.STATE_DIST) ~= 0 then
						port.stateFlags = bit.bor(port.stateFlags, lacp.STATE_COL)
					else
						port.stateFlags = bit.band(port.stateFlags, bit.bnot(lacp.STATE_COL))
						down = true
					end
					port.up = not down
				else
					log:warn("Received unsupported LACPDU")
				end
			end
			bufs:free(rx)
			-- transmit every second
			if getMonotonicTime() > lastUpdate + 1 then
				for i, port in ipairs(ports) do
					if getMonotonicTime() > port.rxStateTimeout then
						port.rxState = "EXPIRED"
						port.stateFlags = bit.bor(lacp.STATE_ACT, lacp.STATE_AGG, lacp.STATE_DEF, lacp.STATE_EXP)
						port.partnerInfo = ffi.new("struct lacp_info")
						port.actorInfo = ffi.new("struct lacp_info")
					end
					if port.rxState == "EXPIRED" then
						port.stateFlags = bit.bor(port.stateFlags, lacp.STATE_EXP)
					else
						port.stateFlags = bit.band(port.stateFlags, bit.bnot(lacp.STATE_EXP))
					end
					txBufs:alloc(lacp.PKT_SIZE)
					local pkt = txBufs[1]:getLacpPacket()
					pkt.eth.src:setString(port.tx.dev:getMacString())
					pkt.lacp.actor:setKey(1) -- TODO: change to support multiple channels
					pkt.lacp.actor:setPortId(port.tx.id + 1000)
					pkt.lacp.actor:setState(port.stateFlags)
					ffi.copy(port.actorInfo, pkt.lacp.actor, ffi.sizeof("struct lacp_info"))
					ffi.copy(pkt.lacp.partner, port.partnerInfo, ffi.sizeof("struct lacp_info"))
					--print("Sending")
					--txBufs[1]:dump()
					port.tx:send(txBufs)
				end
				lastUpdate = getMonotonicTime()
			end
		end
		local numPortsUp = 0
		for i, port in ipairs(ports) do
			if port.up then
				numPortsUp = numPortsUp + 1
			end
		end
		status[channel.name] = { up = numPortsUp, numPorts = #ports, mac = lacpMac }
		dpdk.sleepMillisIdle(1)
	end
end

__MG_LACP_TASK = lacpTask

return lacp

