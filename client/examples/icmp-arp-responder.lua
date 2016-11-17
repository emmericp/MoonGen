local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local utils 	= require "utils"
local log		= require "log"

local arp		= require "proto.arp"
local ip		= require "proto.ip4"
local icmp		= require "proto.icmp"


function master(funny, port, ...)
	if funny and funny ~= "--do-funny-things" then
		return master(nil, funny, port, ...)
	end
	port = tonumber(port)
	if not port or select("#", ...) == 0 or ... == nil then
		log:info("usage: [--do-funny-things] port ip [ip...]")
		return
	end
	
	local dev = device.config(port, 2, 2)
	device.waitForLinks()
	
	dpdk.launchLua(arp.arpTask, {
		{ rxQueue = dev:getRxQueue(1), txQueue = dev:getTxQueue(1), ips = { ... } }
	})

	pingResponder(dev, funny)
end

local DIGITS = { 1, 8 }

local states = {
	"         ",
	"    X    ",
	"   XXX   ",
	"  XXXXX  ",
	" XXXXXXX ",
	"XXXXXXXXX",
	"XXXX XXXX",
	"XXX   XXX",
	"XX     XX",
	"X       X",
}

for i, v in ipairs(states) do
	states[i] = tonumber((v:gsub(" ", DIGITS[1]):gsub("X", DIGITS[2])))
end

local function getSymbol(step)
	return states[step % #states + 1]
end


function pingResponder(dev, funny)
	if funny then
		log:info("Most ping 'clients' do not support the --do-funny-things option and ignore our responses :(")
		log:info("One notable exception is Linux ping from the iputils package")
	end

	local devMac = dev:getMac(true)
	local rxQueue = dev:getRxQueue(0)
	local txQueue = dev:getTxQueue(0)

	local rxMem = memory.createMemPool()	
	local rxBufs = rxMem:bufArray(1)
	while dpdk.running() do
		rx = rxQueue:recv(rxBufs)
		if rx > 0 then
			local buf = rxBufs[1]
			local pkt = buf:getIcmpPacket()
			if pkt.ip4:getProtocol() == ip.PROTO_ICMP then
				local tmp = pkt.ip4.src:get()
				pkt.eth.dst:set(pkt.eth.src:get())
				pkt.eth.src:set(devMac)
				pkt.ip4.src:set(pkt.ip4.dst:get())
				pkt.ip4.dst:set(tmp)
				pkt.icmp:setType(icmp.ECHO_REPLY.type)
				if funny then
					local ts = pkt.icmp.body.uint32[1]
					local seq = bswap16(pkt.icmp.body.uint16[1])
					local symbol = getSymbol(seq)
					ts = ts - symbol
					seq = seq + 10000
					pkt.ip4.ttl = math.min(63 - pkt.ip4.ttl + 100, 200)
					pkt.icmp.body.uint32[1] = ts
					pkt.icmp.body.uint16[1] = bswap16(seq)
				end
				pkt.ip4:setChecksum(0)
				pkt.icmp:calculateChecksum(pkt.ip4:getLength() - pkt.ip4:getHeaderLength() * 4)
				rxBufs:offloadIPChecksums()
				txQueue:send(rxBufs)
			else
				rxBufs:freeAll()
			end
		end
	end
end

