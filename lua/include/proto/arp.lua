local ffi = require "ffi"

require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local memory = require "memory"
local filter = require "filter"

local eth = require "proto.ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local format = string.format
local istype = ffi.istype

local arp = {}


--------------------------------------------------------------------------------------------------------
--- ARP constants (c.f. http://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml)
--------------------------------------------------------------------------------------------------------

-- hrd
arp.HARDWARE_ADDRESS_TYPE_ETHERNET = 1

-- pro (for ethernet based protocols uses ether type numbers)
arp.PROTO_ADDRESS_TYPE_IP = 0x0800

-- op
arp.OP_REQUEST = 1
arp.OP_REPLY = 2


--------------------------------------------------------------------------------------------------------
--- ARP header
--------------------------------------------------------------------------------------------------------

local arpHeader = {}
arpHeader.__index = arpHeader

--- Set the hardware address type.
-- @param int Type as 16 bit integer.
function arpHeader:setHardwareAddressType(int)
	int = int or arp.HARDWARE_ADDRESS_TYPE_ETHERNET
	self.hrd = hton16(int)
end

--- Retrieve the hardware address type.
-- @return Type as 16 bit integer.
function arpHeader:getHardwareAddressType()
	return hton16(self.hrd)
end

--- Retrieve the hardware address type.
-- @return Type in string format.
function arpHeader:getHardwareAddressTypeString()
	local type = self:getHardwareAddressType()
	if type == arp.HARDWARE_ADDRESS_TYPE_ETHERNET then
		return "Ethernet"
	else
		return format("0x%04x", type)
	end
end
	
function arpHeader:setProtoAddressType(int)
	int = int or arp.PROTO_ADDRESS_TYPE_IP
	self.pro = hton16(int)
end

function arpHeader:getProtoAddressType()
	return hton16(self.pro)
end

function arpHeader:getProtoAddressTypeString()
	local type = self:getProtoAddressType()
	if type == arp.PROTO_ADDR_TYPE_IP then
		return "IPv4"
	else
		return format("0x%04x", type)
	end
end

function arpHeader:setHardwareAddressLength(int)
	int = int or 6
	self.hln = int
end

function arpHeader:getHardwareAddressLength()
	return self.hln
end

function arpHeader:getHardwareAddressLengthString()
	return self:getHardwareAddressLength()
end

function arpHeader:setProtoAddressLength(int)
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
	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		return "Request"
	elseif op == arp.OP_REPLY then
		return "Reply"
	else
		return op
	end
end

function arpHeader:setHardwareSrc(addr)
	self.sha:set(addr)
end

function arpHeader:getHardwareSrc()
	return self.sha:get()
end

function arpHeader:setHardwareSrcString(addr)
	self.sha:setString(addr)
end

function arpHeader:getHardwareSrcString()
	return self.sha:getString()
end

function arpHeader:setHardwareDst(addr)
	self.tha:set(addr)
end

function arpHeader:getHardwareDst()
	return self.tha:get()
end

function arpHeader:setHardwareDstString(addr)
	self.tha:setString(addr)
end

function arpHeader:getHardwareDstString()
	return self.tha:getString()
end

function arpHeader:setProtoSrc(addr)
	self.spa:set(addr)
end

function arpHeader:getProtoSrc()
	return self.spa:get()
end

function arpHeader:setProtoSrcString(addr)
	self.spa:setString(addr)
end

function arpHeader:getProtoSrcString()
	return self.spa:getString()
end

function arpHeader:setProtoDst(addr)
	self.tpa:set(addr)
end

function arpHeader:getProtoDst()
	return self.tpa:get()
end

function arpHeader:setProtoDstString(addr)
	self.tpa:setString(addr)
end

function arpHeader:getProtoDstString()
	return self.tpa:getString()
end

function arpHeader:fill(args)
	args = args or {}
	
	self:setHardwareAddressType(args.arpHardwareAddressType)
	self:setProtoAddressType(args.arpProtoAddressType)
	self:setHardwareAddressLength(args.arpHardwareAddressLength)
	self:setProtoAddressLength(args.arpProtoAddressLength)
	self:setOperation(args.arpOperation)

	args.arpHardwareSrc = args.arpHardwareSrc or "01:02:03:04:05:06"
	args.arpHardwareDst = args.arpHardwareDst or "07:08:09:0a:0b:0c"
	args.arpProtoSrc = args.arpProtoSrc or "0.1.2.3"
	args.arpProtoDst = args.arpProtoDst or "4.5.6.7"
	
	-- if for some reason the address is in 'struct mac_address'/'union ipv4_address' format, cope with it
	if type(args.arpHardwareSrc) == "string" then
		self:setHardwareSrcString(args.arpHardwareSrc)
	else
		self:setHardwareSrc(args.arpHardwareSrc)
	end
	if type(args.arpHardwareDst) == "string" then
		self:setHardwareDstString(args.arpHardwareDst)
	else
		self:setHardwareDst(args.arpHardwareDst)
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
	return { arpHardwareAddressType 	= self:getHardwareAddressType(),
			 arpProtoAddressType 		= self:getProtoAddressType(),
			 arpHardwareAddressLength	= self:getHardwareAddressLength(),
			 arpProtoAddressLength		= self:getProtoAddressLength(),
			 arpOperation				= self:getOperation(),
			 arpHardwareSrc				= self:getHardwareSrc(),
			 arpHardwareDst				= self:getHardwareDst(),
			 arpProtoSrc				= self:getProtoSrc(),
			 arpProtoDst				= self:getProtoDst() 
		 }
end

--- Retrieve the values of all members.
-- @return Values in string format.
function arpHeader:getString()
	local str = "ARP hrd " 			.. self:getHardwareAddressTypeString() 
				.. " (hln " 		.. self:getHardwareAddressLengthString() 
				.. ") pro " 		.. self:getProtoAddressTypeString() 
				.. " (pln " 		.. self:getProtoAddressLength(String) 
				.. ") op " 			.. self:getOperationString()

	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		str = str .. " who-has " 	.. self:getProtoDstString() 
				  .. " (" 			.. self:getHardwareDstString() 
				  .. ") tell " 		.. self:getProtoSrcString() 
				  .. " (" 			.. self:getHardwareSrcString() 
				  .. ")"
	elseif op == arp.OP_REPLY then
		str = str .. " " 			.. self:getProtoSrcString() 
				  .. " is-at " 		.. self:getHardwareSrcString() 
				  .. " (for " 		.. self:getProtoDstString() 
				  .. " @ " 			.. self:getHardwareDstString() 
				  .. ")"
	else
		str = str .. " " 			.. self:getHardwareSrcString() 
				  .. " > " 			.. self:getHardwareDstString() 
				  .. " " 			.. self:getProtoSrcString() 
				  .. " > " 			.. self:getProtoDstString()
	end

	return str
end


---------------------------------------------------------------------------------
--- ARP packet
---------------------------------------------------------------------------------

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

	args.ethType = args.ethType or eth.TYPE_ARP

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
	dumpPacket(self, bytes, self.eth, self.arp)
end


---------------------------------------------------------------------------------
--- ARP Handler Task
---------------------------------------------------------------------------------

--- Arp handler task, responds to ARP queries for given IPs
-- TODO: implement arp request support, but this depends on some other features (something like globals)
arp.arpTask = "__MG_ARP_TASK"

local function arpTask(rxQueue, txQueue, ips)
	if type(ips) ~= "table" then
		ips = { ips }
	end
	local ipToMac = {}
	for i, v in ipairs(ips) do
		if type(v) == "string" then
			v = parseIPAddress(v)
			ips[i] = v
		end
		ipToMac[v] = true -- TODO: support different MACs for different IPs
	end
	if rxQueue.dev ~= txQueue.dev then
		error("both queues must belong to the same device")
	end

	local dev = rxQueue.dev
	local devMac = dev:getMac()
	local rxBufs = memory.createBufArray(1)
	local txMem = memory.createMemPool(function(buf)
		buf:getArpPacket():fill{ 
			ethSrc			= devMac,  
			arpOperation	= arp.OP_REPLY,
			arpHardwareSrc	= devMac,
			arpProtoSrc 	= devIP,
			pktLength		= 60
		}
	end)
	local txBufs = txMem:bufArray(1)
	dev:l2Filter(eth.TYPE_ARP, rxQueue)
	
	
	while dpdk.running() do
		rx = rxQueue:tryRecv(rxBufs, 10000)
		assert(rx <= 1)
		if rx > 0 then
			local rxPkt = rxBufs[1]:getArpPacket()
			if rxPkt.eth:getType() == eth.TYPE_ARP and rxPkt.arp:getOperation() == arp.OP_REQUEST then
				local ip = rxPkt.arp:getProtoDst()
				local mac = ipToMac[ip]
				if mac then
					if mac == true then
						mac = devMac
					end
					txBufs:alloc(60)
					local pkt = txBufs[1]:getArpPacket()
					pkt.eth:setDst(rxPkt.eth:getSrc())
					pkt.arp:setHardwareDst(rxPkt.arp:getHardwareSrc())
					pkt.arp:setProtoDst(rxPkt.arp:getProtoSrc())
					pkt.arp:setProtoSrc(ip)
					txQueue:send(txBufs)
				end
			end
			rxBufs:freeAll()
		end
		dpdk.sleepMillisIdle(1)
	end
end

__MG_ARP_TASK = arpTask


---------------------------------------------------------------------------------
--- Metatypes
---------------------------------------------------------------------------------

ffi.metatype("struct arp_header", arpHeader)
ffi.metatype("struct arp_packet", arpPacket)

return arp

