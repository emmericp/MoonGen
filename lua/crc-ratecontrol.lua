local device = require "device"
local pkt    = require "packet"
local memory = require "memory"
local ffi    = require "ffi"
local log    = require "log"

local txQueue = device.__txQueuePrototype
local device = device.__devicePrototype
local C = ffi.C

ffi.cdef[[
	void moongen_send_all_packets_with_delay_bad_crc(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct mempool* pool, uint32_t min_pkt_size);
]]

local mempool
--- Send rate-controlled packets by filling gaps with invalid packets.
-- @param bufs
-- @param targetRate optional, hint to the driver which total rate you are trying to achieve.
--   increases precision at low non-cbr rates
-- @param n optional, number of packets to send (defaults to full bufs)
function txQueue:sendWithDelay(bufs, targetRate, n)
	if not self.dev.crcPatch then
		log:fatal("Driver does not support disabling the CRC flag. This feature requires a patched driver.")
	end
	targetRate = targetRate or 14.88
	self.used = true
	mempool = mempool or memory.createMemPool{
		func = function(buf)
			-- this is tcp packet because the netfpga/OSNT system we use for testing this
			-- cannot handle all-zero packets properly (filters get confused)
			-- the actual contents of the packets don't matter since their CRC is invalid anways
			local pkt = buf:getTcpPacket()
			pkt:fill()
		end
	}
	n = n or bufs.size
	local avgPacketSize = 1.25 / (targetRate * 2) * 1000
	local minPktSize = self.dev.minPacketSize or 64
	local maxPktRate = self.dev.maxPacketRate or 14.88
	-- allow smaller packets at low rates
	if targetRate < maxPktRate / 2 then
		minPktSize = minPktSize + 20
	else
		minPktSize = math.floor(10 * 10^9 / 10^6 / 8 / maxPktRate)
	end
	C.moongen_send_all_packets_with_delay_bad_crc(self.id, self.qid, bufs.array, n, mempool, minPktSize)
	return bufs.size
end

--- Set the time to wait before the packet is sent for software rate-controlled send methods.
--- @param delay The time to wait before this packet \(in bytes, i.e. 1 == 0.8 nanoseconds on 10 GbE\)
function pkt:setDelay(delay)
	self.udata64 = delay
end

--- sets the delay (cf. pkt:setDelay) to match a given packet rate in Mpps
function pkt:setRate(rate)
	self.udata64 = 10^10 / 8 / (rate * 10^6) - self.pkt_len - 24
end

ffi.cdef[[
uint64_t moongen_get_bad_pkts_sent(uint8_t port_id);
uint64_t moongen_get_bad_bytes_sent(uint8_t port_id);
]]

local function hookTxStats(dev)
	if dev.__txStatsHooked then
		return
	end
	dev.__txStatsHooked = true
	local old = dev.getTxStats
	if old then
		dev.getTxStats = function(self)
			local pkts, bytes = old(self)
			local badPkts = tonumber(C.moongen_get_bad_pkts_sent(self.id))
			local badBytes = tonumber(C.moongen_get_bad_bytes_sent(self.id))
			return pkts - badPkts, bytes - badBytes
		end
	end
end

hookTxStats(device)
for driver, dev in pairs(require("drivers")) do
	if tostring(driver):match("^net_") and type(dev) == "table" then
		hookTxStats(dev)
	end
end

