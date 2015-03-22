local mod = {}

local ffi		= require "ffi"
local dpdkc		= require "dpdkc"
local dpdk		= require "dpdk"
local memory	= require "memory"

mod.PCI_ID_X540		= 0x80861528
mod.PCI_ID_82599	= 0x808610FB
mod.PCI_ID_82580	= 0x8086150E
mod.PCI_ID_82576	= 0x80861526

function mod.init()
	dpdkc.rte_pmd_init_all_export();
	dpdkc.rte_eal_pci_probe();
end

function mod.numDevices()
	return dpdkc.rte_eth_dev_count();
end

local dev = {}
dev.__index = dev
dev.__type = "device"

function dev:__tostring()
	return ("[Device: id=%d]"):format(self.id)
end

function dev:__serialize()
	return ('local dev = require "device" return dev.get(%d)'):format(self.id), true
end

local txQueue = {}
txQueue.__index = txQueue
txQueue.__type = "txQueue"

function txQueue:__tostring()
	return ("[TxQueue: id=%d, qid=%d]"):format(self.id, self.qid)
end

function txQueue:__serialize()
	return ('local dev = require "device" return dev.get(%d):getTxQueue(%d)'):format(self.id, self.qid), true
end

local rxQueue = {}
rxQueue.__index = rxQueue
rxQueue.__type = "rxQueue"

function rxQueue:__tostring()
	return ("[RxQueue: id=%d, qid=%d]"):format(self.id, self.qid)
end

function rxQueue:__serialize()
	return ('local dev = require "device" return dev.get(%d):getRxQueue(%d)'):format(self.id, self.qid), true
end

local devices = {}
function mod.config(port, mempool, rxQueues, txQueues, rxDescs, txDescs)
	if devices[port] and devices[port].initialized then
		printf("[WARNING] Device %d already configured, skipping initilization", port)
		return mod.get(port)
	end
	if not mempool or type(mempool) == "number" then
		return mod.config(port, memory.createMemPool(nil, dpdkc.get_socket(port)), mempool, rxQueues, txQueues, rxDescs)
	end
	if rxQueues == 0 or txQueues == 0 then
		-- dpdk does not like devices without rx/tx queues :(
		errorf("cannot initialize device without %s queues", rxQueues == 0 and txQueues == 0 and "rx and tx" or rxQueues == 0 and "rx" or "tx")
	end
	rxQueues = rxQueues or 1
	txQueues = txQueues or 1
	rxDescs = rxDescs or 0
	txDescs = txDescs or 0
	-- TODO: support options
	local rc = dpdkc.configure_device(port, rxQueues, txQueues, rxDescs, txDescs, mempool)
	if rc ~= 0 then
		errorf("could not configure device %d: error %d", port, rc)
	end
	local dev = mod.get(port)
	dev.initialized = true
	return dev
end

function mod.get(id)
	if devices[id] then
		return devices[id]
	end
	devices[id] = setmetatable({ id = id, rxQueues = {}, txQueues = {} }, dev)
	if MOONGEN_TASK_NAME ~= "master" then
		-- check the NUMA association if we are running in a worker thread
		-- (it's okay to do the initial config from the wrong socket, but sending packets from it is a bad idea)
		local devSocket = devices[id]:getSocket()
		local core, threadSocket = dpdk.getCore()
		if devSocket ~= threadSocket then
			printf("[WARNING] You are trying to use %s (attached to the CPU socket %d) from a thread on core %d on socket %d!",
				devices[id], devSocket, core, threadSocket)
			printf("[WARNING] This can significantly impact the performance or even not work at all")
			printf("[WARNING] You can change the used CPU cores in dpdk-conf.lua or by using dpdk.launchLuaOnCore(core, ...)")
		end
	end
	return devices[id]
end

function dev:getTxQueue(id)
	local tbl = self.txQueues
	if tbl[id] then
		return tbl[id]
	end
	tbl[id] = setmetatable({ id = self.id, qid = id, dev = self }, txQueue)
	tbl[id]:getTxRate()
	return tbl[id]
end

function dev:getRxQueue(id)
	local tbl = self.rxQueues
	if tbl[id] then
		return tbl[id]
	end
	tbl[id] = setmetatable({ id = self.id, qid = id, dev = self }, rxQueue)
	return tbl[id]
end


--- Waits until all given devices are initialized by calling wait() on them.
function mod.waitForLinks(...)
	local ports
	if select("#", ...) == 0 then
		ports = {}
		for port, dev in pairs(devices) do
			if dev.initialized then
				ports[#ports + 1] = port
			end
		end
	else
		ports = { ... }
	end
	print("Waiting for ports to come up...")
	local portsUp = 0
	local portsSeen = {} -- do not wait twice if a port occurs more than once (e.g. if rx == tx)
	for i, port in ipairs(ports) do
		local port = mod.get(port)
		if not portsSeen[port] then
			portsSeen[port] = true
			portsUp = portsUp + (port:wait() and 1 or 0)
		end
	end
	printf("%d ports are up.", portsUp)
end


--- Wait until the device is fully initialized and up to 9 seconds to establish a link.
-- This function then reports the current link state on stdout
function dev:wait()
	local link = self:getLinkStatus()
	self.speed = link.speed
	printf("Port %d (%s) is %s: %s%s MBit/s", self.id, self:getMacString(), link.status and "up" or "DOWN", link.duplexAutoneg and "" or link.duplex and "full-duplex " or "half-duplex ", link.speed)
	return link.status
end

function dev:getLinkStatus()
	local link = ffi.new("struct rte_eth_link")
	dpdkc.rte_eth_link_get(self.id, link)
	return { status = link.link_status == 1, duplexAutoneg = link.link_duplex == 0, duplex = link.link_duplex == 2, speed = link.link_speed }
end

function dev:getMacString()
	local buf = ffi.new("char[20]")
	dpdkc.get_mac_addr(self.id, buf)
	return ffi.string(buf)
end

function dev:getMac()
	-- TODO: optimize
	return parseMacAddress(self:getMacString())
end

function dev:getPciId()
	return dpdkc.get_pci_id(self.id)
end

function dev:getSocket()
	return dpdkc.get_socket(self.id)
end

local deviceNames = {
	[mod.PCI_ID_82599]	= "82599EB 10-Gigabit SFI/SFP+ Network Connection",
	[mod.PCI_ID_82580]	= "82580 Gigabit Network Connection",
	[mod.PCI_ID_82576]	= "82576 Gigabit Network Connection",
	[mod.PCI_ID_X540]	= "Ethernet Controller 10-Gigabit X540-AT2",
}

function dev:getName()
	local id = self:getPciId()
	return deviceNames[id] or ("unknown NIC (PCI ID %x:%x)"):format(bit.rshift(id, 16), bit.band(id, 0xFFFF))
end

function mod.getDeviceName(port)
	return mod.get(port):getName()
end

function mod.getDevices()
	local result = {}
	for i = 0, dpdkc.rte_eth_dev_count() - 1 do
		local dev = mod.get(i)
		result[#result + 1] = { id = i, mac = dev:getMacString(i), name = dev:getName(i) }
	end
	return result
end

-- FIXME: only tested on X540, 82599 and 82580 chips
-- these functions must be wrapped in a device-specific way
-- rx stats
local GPRC	= 0x00004074
local GORCL = 0x00004088
local GORCH	= 0x0000408C

-- tx stats
local GPTC	= 0x00004080
local GOTCL	= 0x00004090
local GOTCH	= 0x00004094

--- get the number of packets received since the last call to this function
function dev:getRxStats()
	return dpdkc.read_reg32(self.id, GPRC), dpdkc.read_reg32(self.id, GORCL) + dpdkc.read_reg32(self.id, GORCH) * 2^32
end

function dev:getTxStats()
	local badPkts = tonumber(dpdkc.get_bad_pkts_sent(self.id))
	local badBytes = tonumber(dpdkc.get_bad_bytes_sent(self.id))
	return dpdkc.read_reg32(self.id, GPTC) - badPkts, dpdkc.read_reg32(self.id, GOTCL) + dpdkc.read_reg32(self.id, GOTCH) * 2^32 - badBytes
end


-- TODO: figure out how to actually acquire statistics in a meaningful way for dropped packets :/
function dev:getRxStatsAll()
	local stats = ffi.new("struct rte_eth_stats")
	dpdkc.rte_eth_stats_get(self.id, stats)
	return stats
end

local RTTDQSEL = 0x00004904

--- Set the tx rate of a queue in MBit/s.
-- This sets the payload rate, not to the actual wire rate, i.e. preamble, SFD, and IFG are ignored.
-- The X540 and 82599 chips seem to have a hardware bug (?): they seem use the wire rate in some point of the throttling process.
-- This causes erratic behavior for rates >= 64/84 * WireRate when using small packets.
-- The function is non-linear (not even monotonic) for such rates.
-- The function prints a warning if such a rate is configured.
-- A simple work-around for this is using two queues with 50% of the desired rate.
-- Note that this changes the inter-arrival times as the rate control of both queues is independent.
function txQueue:setRate(rate)
	if self.dev:getPciId() ~= mod.PCI_ID_82599 and self.dev:getPciId() ~= mod.PCI_ID_X540 then
		error("tx rate control not yet implemented for this NIC")
	end
	local speed = self.dev:getLinkStatus().speed
	if speed <= 0 then
		print("WARNING: link down, assuming 10 GbE connection")
		speed = 10000
	end
	if rate <= 0 then
		rate = speed
	end
	self.rate = math.min(rate, speed)
	self.speed = speed
	local link = self.dev:getLinkStatus()
	self.speed = link.speed
	rate = rate / speed
	-- the X540 and 82599 chips have a hardware bug: they assume that the wire size of an
	-- ethernet frame is 64 byte when it is actually 84 byte (8 byte preamble/SFD, 12 byte IFG)
	-- TODO: software fallback for bugged rates and unsupported NICs
	if rate >= (64 * 64) / (84 * 84) and rate < 1 then
		print("WARNING: rates with a payload rate >= 64/84% do not work properly with small packets due to a hardware bug, see documentation for details")
	end
	if rate <= 0 then
		error("rate must be > 0")
	end
	if rate >= 1 then
		self:setTxRateRaw(0, true)
	else
		self:setTxRateRaw(1 / rate)
	end
end

function txQueue:setRateMpps(rate, pktSize)
	pktSize = pktSize or 60
	self:setRate(rate * (pktSize + 4) * 8)
end

local RF_X540_82599 = 0x00004984
local RF_ENABLE_BIT = bit.lshift(1, 31)

function txQueue:setTxRateRaw(rate, disable)
	dpdkc.write_reg32(self.id, RTTDQSEL, self.qid)
	if disable then
		dpdkc.write_reg32(self.id, RF_X540_82599, 0)
		return
	end
	-- 10.14 fixed-point
	local rateInt = math.floor(rate)
	local rateDec = math.floor((rate - rateInt) * 2^14)
	dpdkc.write_reg32(self.id, RF_X540_82599, bit.bor(bit.lshift(rateInt, 14), rateDec, RF_ENABLE_BIT))
end

function txQueue:getTxRate()
	local link = self.dev:getLinkStatus()
	self.speed = link.speed > 0 and link.speed or 10000
	dpdkc.write_reg32(self.id, RTTDQSEL, self.qid)
	local reg = dpdkc.read_reg32(self.id, RF_X540_82599)
	if reg == 0 then
		self.rate = nil
		return self.speed
	end
	-- 10.14 fixed-point
	local rateInt = bit.band(bit.rshift(reg, 14), 0x3FFF)
	local rateDec = bit.band(reg, 0x3FF)
	self.rate = (1 / (rateInt + rateDec / 2^14)) * self.speed
	return self.rate
end

function txQueue:send(bufs)
	dpdkc.send_all_packets(self.id, self.qid, bufs.array, bufs.size);
	return bufs.size
end

do
	local mempool
	function txQueue:sendWithDelay(bufs, method)
		mempool = mempool or memory.createMemPool(2047, nil, nil, 4095)
		method = method or "crc"
		if method == "crc" then
			dpdkc.send_all_packets_with_delay_bad_crc(self.id, self.qid, bufs.array, bufs.size, mempool)
		elseif method == "size" then
			dpdkc.send_all_packets_with_delay_invalid_size(self.id, self.qid, bufs.array, bufs.size, mempool)
		else
			errorf("unknown delay method %s", method)
		end
		return bufs.size
	end
end


--- Receive packets from a rx queue.
-- Returns as soon as at least one packet is available.
function rxQueue:recv(bufArray)
	while dpdk.running() do
		local rx = dpdkc.rte_eth_rx_burst_export(self.id, self.qid, bufArray.array, bufArray.size)
		if rx > 0 then
			return rx
		end
	end
	return 0
end

function rxQueue:recvAll(bufArray)
	error("NYI")
end

--- Receive packets from a rx queue with a timeout.
function rxQueue:tryRecv(bufArray, maxWait)
	maxWait = maxWait or math.huge
	while maxWait >= 0 do
		local rx = dpdkc.rte_eth_rx_burst_export(self.id, self.qid, bufArray.array, bufArray.size)
		if rx > 0 then
			return rx
		end
		maxWait = maxWait - 1
		-- don't sleep pointlessly
		if maxWait < 0 then
			break
		end
		dpdk.sleepMicros(1)
	end
	return 0
end

-- export prototypes to extend them in other modules (TODO: use a proper 'class' system with mix-ins or something)
mod.__devicePrototype = dev
mod.__txQueuePrototype = txQueue
mod.__rxQueuePrototype = rxQueue

return mod

