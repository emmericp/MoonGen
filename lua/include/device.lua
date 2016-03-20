---------------------------------
--- @file device.lua
--- @brief Device ...
--- @todo TODO docu
---------------------------------

local mod = {}

local ffi		= require "ffi"
local dpdkc		= require "dpdkc"
local dpdk		= require "dpdk"
local memory	= require "memory"
local serpent 	= require "Serpent"
local errors 	= require "error"
local log 		= require "log"
require "headers"

-- FIXME: fix this ugly duplicated code enum
mod.RSS_FUNCTION_IPV4     = 1
mod.RSS_FUNCTION_IPV4_TCP = 2
mod.RSS_FUNCTION_IPV4_UDP = 3
mod.RSS_FUNCTION_IPV6     = 4
mod.RSS_FUNCTION_IPV6_TCP = 5
mod.RSS_FUNCTION_IPV6_UDP = 6

ffi.cdef[[
  void rte_eth_macaddr_get 	( 	uint8_t  	port_id,
		struct ether_addr *  	mac_addr 
	) 	
]]

mod.PCI_ID_X540		= 0x80861528
mod.PCI_ID_X520		= 0x8086154D
mod.PCI_ID_X520_T2	= 0x8086151C
mod.PCI_ID_82599	= 0x808610FB
mod.PCI_ID_82580	= 0x8086150E
mod.PCI_ID_I350		= 0x80861521
mod.PCI_ID_82576	= 0x80861526
mod.PCI_ID_XL710	= 0x80861583

mod.PCI_ID_82599_VF	= 0x808610ed

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

--- Configure a device
--- @param args A table containing the following named arguments
---   port Port to configure
---   mempool optional (default = create a new mempool) Mempool to associate to the device
---   rxQueues optional (default = 1) Number of RX queues to configure 
---   txQueues optional (default = 1) Number of TX queues to configure 
---   rxDescs optional (default = 512)
---   txDescs optional (default = 1024)
---   speed optional (default = 0)
---   dropEnable optional (default = true)
---   rssNQueues optional (default = 0) If this is >0 RSS will be activated for
---    this device. Incomming packates will be distributed to the
---    rxQueues number 0 to (rssNQueues - 1). For a fair distribution use one of
---    the following values (1, 2, 4, 8, 16). Values greater than 16 are not
---    allowed.
---   rssFunctions optional (default = all supported functions) A Table,
---    containing hashing methods, which can be used for RSS.
---    Possible methods are:
---      dev.RSS_FUNCTION_IPV4    
---      dev.RSS_FUNCTION_IPV4_TCP
---      dev.RSS_FUNCTION_IPV4_UDP
---      dev.RSS_FUNCTION_IPV6    
---      dev.RSS_FUNCTION_IPV6_TCP
---      dev.RSS_FUNCTION_IPV6_UDP
---	  disableOffloads optional (default = false) Disable offloading, this
---     speeds up the driver. Note that timestamping is an offload as far
---     as the driver is concerned.
--- @todo FIXME: add description for speed and dropEnable parameters.
function mod.config(...)
	local args = {...}
	if #args > 1 or type((...)) == "number" then
	    -- this is for legacy compatibility when calling the function  without named arguments
		log:warn("You are using a deprecated method for invoking device.config. config(...) should be used with named arguments. For details: see documentation")
		if not args[2] or type(args[2]) == "number" then
			args.port       = args[1]
			args.rxQueues   = args[2]
			args.txQueues   = args[3]
			args.rxDescs    = args[4]
			args.txDescs    = args[5]
			args.speed      = args[6]
			args.dropEnable = args[7]
		else
			args.port       = args[1]
			args.mempool    = args[2]
			args.rxQueues   = args[3]
			args.txQueues   = args[4]
			args.rxDescs    = args[5]
			args.txDescs    = args[6]
			args.speed      = args[7]
			args.dropEnable = args[8]
		end
	elseif #args == 1 then
		-- here we receive named arguments
		args = args[1]
	else
		log:fatal("Device config needs at least one argument.")
	end

	args.rxQueues = args.rxQueues or 1
	args.txQueues = args.txQueues or 1
	args.rxDescs  = args.rxDescs or 512
	args.txDescs  = args.txDescs or 1024
	args.rssNQueues = args.rssNQueues or 0
	args.rssFunctions = args.rssFunctions or {
		mod.RSS_FUNCTION_IPV4,
		mod.RSS_FUNCTION_IPV4_UDP,
		mod.RSS_FUNCTION_IPV4_TCP,
		mod.RSS_FUNCTION_IPV6,
		mod.RSS_FUNCTION_IPV6_UDP,
		mod.RSS_FUNCTION_IPV6_TCP
	}
	-- create a mempool with enough memory to hold tx, as well as rx descriptors
	-- (tx descriptors for forwarding applications when rx descriptors from one of the device are directly put into a tx queue of another device)
	-- FIXME: n = 2^k-1 would save memory
	args.mempool = args.mempool or memory.createMemPool{n = args.rxQueues * args.rxDescs + args.txQueues * args.txDescs, socket = dpdkc.get_socket(args.port)}
	if devices[args.port] and devices[args.port].initialized then
		log:warn("Device %d already configured, skipping initilization", args.port)
		return mod.get(args.port)
	end
	args.speed = args.speed or 0
	args.dropEnable = args.dropEnable == nil and true
	if args.rxQueues == 0 or args.txQueues == 0 then
		-- dpdk does not like devices without rx/tx queues :(
		log:fatal("Cannot initialize device without %s queues", args.rxQueues == 0 and args.txQueues == 0 and "rx and tx" or args.rxQueues == 0 and "rx" or "tx")
	end
	-- configure rss stuff
	local rss_enabled = 0
	local rss_hash_mask = ffi.new("struct mg_rss_hash_mask")
	if(args.rssNQueues > 0) then
		for i, v in ipairs(args.rssFunctions) do
			if (v == mod.RSS_FUNCTION_IPV4) then
				rss_hash_mask.ipv4 = 1
			end
			if (v == mod.RSS_FUNCTION_IPV4_TCP) then
				rss_hash_mask.tcp_ipv4 = 1
			end
			if (v == mod.RSS_FUNCTION_IPV4_UDP) then
				rss_hash_mask.udp_ipv4 = 1
			end
			if (v == mod.RSS_FUNCTION_IPV6) then
				rss_hash_mask.ipv6 = 1
			end
			if (v == mod.RSS_FUNCTION_IPV6_TCP) then
				rss_hash_mask.tcp_ipv6 = 1
			end
			if (v == mod.RSS_FUNCTION_IPV6_UDP) then
				rss_hash_mask.udp_ipv6 = 1
			end
		end
		rss_enabled = 1
	end
	-- TODO: support options
	local rc = dpdkc.configure_device(args.port, args.rxQueues, args.txQueues, args.rxDescs, args.txDescs, args.speed, args.mempool, args.dropEnable, rss_enabled, rss_hash_mask, args.disableOffloads or false)
	if rc ~= 0 then
	    log:fatal("Could not configure device %d: error %d", args.port, rc)
	end
	local dev = mod.get(args.port)
	dev.initialized = true
	if rss_enabled == 1 then
		dev:setRssNQueues(args.rssNQueues)
	end
	dev:setPromisc(true)
	return dev
end

ffi.cdef[[
/**
 * A structure used to configure Redirection Table of  the Receive Side
 * Scaling (RSS) feature of an Ethernet port.
 */
struct rte_eth_rss_reta {
	/** First 64 mask bits indicate which entry(s) need to updated/queried. */
	uint64_t mask_lo;
	/** Second 64 mask bits indicate which entry(s) need to updated/queried. */
	uint64_t mask_hi;
	uint8_t reta[128];  /**< 128 RETA entries*/
};

int mg_rte_eth_dev_rss_reta_update 	( 	uint8_t  	port,
		struct rte_eth_rss_reta *  	reta_conf 
	);
int rte_eth_dev_rss_reta_update 	( 	uint8_t  	port,
		struct rte_eth_rss_reta *  	reta_conf 
	);
]]

function dev:setRssNQueues(n)
  if(n>16)then
    log:fatal("Maximum possible numbers of RSS queues is 16")
    return
  end
  if(({[1]=1, [2]=1, [4]=1, [8]=1, [16]=1})[n] == nil) then
    log:warn("RSS distribution to queues will not be fair. Fair distribution is only achieved with a number of Queues equal to 1, 2, 4, 8 or 16. However you are currently using %d queues", n)
  end
  local reta = ffi.new("struct rte_eth_rss_reta")

  local npq = 128/n
  local queue = 0
  for i=0,127 do
    reta.reta[i] = queue
    if (queue < n - 1) then
      queue = queue+1
    else
      queue = 0
    end
  end

  -- the mg_ version of rte_eth_dev_rss_reta_update() will also write the mask
  -- to the reta_config struct, as lua can not do 64bit unsigned int operations.
  local ret = ffi.C.mg_rte_eth_dev_rss_reta_update(self.id, reta)
  if (ret ~= 0) then
    log:fatal("Error setting up RETA table: " .. errors.getstr(-ret))
  end
end


function mod.get(id)
	if devices[id] then
		return devices[id]
	end
	devices[id] = setmetatable({ id = id, rxQueues = {}, txQueues = {} }, dev)
	if MOONGEN_TASK_NAME ~= "master" and not MOONGEN_IGNORE_BAD_NUMA_MAPPING then
		-- check the NUMA association if we are running in a worker thread
		-- (it's okay to do the initial config from the wrong socket, but sending packets from it is a bad idea)
		local devSocket = devices[id]:getSocket()
		local core, threadSocket = dpdk.getCore()
		if devSocket ~= threadSocket then
			log:warn("You are trying to use %s (attached to the CPU socket %d) from a thread on core %d on socket %d!",
				devices[id], devSocket, core, threadSocket)
			log:warn("This can significantly impact the performance or even not work at all")
			log:warn("You can change the used CPU cores in dpdk-conf.lua or by using dpdk.launchLuaOnCore(core, ...)")
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
	log:info("Waiting for devices to come up...")
	local portsUp = 0
	local portsSeen = {} -- do not wait twice if a port occurs more than once (e.g. if rx == tx)
	for i, port in ipairs(ports) do
		local port = mod.get(port)
		if not portsSeen[port] then
			portsSeen[port] = true
			portsUp = portsUp + (port:wait() and 1 or 0)
		end
	end
	log:info(green("%d devices are up.", portsUp))
end


--- Wait until the device is fully initialized and up to maxWait seconds to establish a link.
-- @param maxWait maximum number of seconds to wait for the link, default = 9
-- This function then reports the current link state on stdout
function dev:wait(maxWait)
	maxWait = maxWait or 9
	local link
	repeat
		link = self:getLinkStatus()
		if maxWait > 0 then
			dpdk.sleepMillisIdle(1000)
			maxWait = maxWait - 1
		else
			break
		end
	until link.status
	self.speed = link.speed
	log:info("Device %d (%s) is %s: %s%s MBit/s", self.id, self:getMacString(), link.status and "up" or "DOWN", link.duplexAutoneg and "" or link.duplex and "full-duplex " or "half-duplex ", link.speed)
	return link.status
end


function dev:getLinkStatus()
	local link = ffi.new("struct rte_eth_link")
	dpdkc.rte_eth_link_get_nowait(self.id, link)
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

function dev:setPromisc(enable)
	if enable then
		dpdkc.rte_eth_promiscuous_enable(self.id)
	else
		dpdkc.rte_eth_promiscuous_disable(self.id)
	end
end

function dev:addMac(mac)
	local rc = dpdkc.rte_eth_dev_mac_addr_add(self.id, parseMacAddress(mac), 0)
	if rc ~= 0 then
		log:fatal("could not add mac: %d", rc)
	end
end

function dev:removeMac(mac)
	local rc = dpdkc.rte_eth_dev_mac_addr_remove(self.id, parseMacAddress(mac))
	if rc ~= 0 then
		log:fatal("could not remove mac: %d", rc)
	end
end

function dev:getPciId()
	return dpdkc.get_pci_id(self.id)
end

function dev:getSocket()
	return dpdkc.get_socket(self.id)
end

local deviceNames = {
	[mod.PCI_ID_82576]	= "82576 Gigabit Network Connection",
	[mod.PCI_ID_82580]	= "82580 Gigabit Network Connection",
	[mod.PCI_ID_I350]	= "I350 Gigabit Network Connection",
	[mod.PCI_ID_82599]	= "82599EB 10-Gigabit SFI/SFP+ Network Connection",
	[mod.PCI_ID_X520]	= "Ethernet 10G 2P X520 Adapter", -- Dell-branded NIC with an 82599
	[mod.PCI_ID_X520_T2]	= "82599EB 10G 2xRJ45 X520-T2 Adapter",
	[mod.PCI_ID_X540]	= "Ethernet Controller 10-Gigabit X540-AT2",
	[mod.PCI_ID_XL710]	= "Ethernet Controller LX710 for 40GbE QSFP+",
	[mod.PCI_ID_82599_VF]	= "Intel Corporation 82599 Ethernet Controller Virtual Function",
}

function dev:getName()
	local id = self:getPciId()
	return deviceNames[id] and green(deviceNames[id]) or red(("unknown NIC (PCI ID %x:%x)"):format(bit.rshift(id, 16), bit.band(id, 0xFFFF)))
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

local function readCtr32(id, addr, last)
	local val = dpdkc.read_reg32(id, addr)
	local diff = val - last
	if diff < 0 then
		diff = 2^32 + diff
	end
	return diff, val
end

local function readCtr48(id, addr, last)
	local addrl = addr
	local addrh = addr + 4
	-- TODO: we probably need a memory fence here
	-- however, the intel driver doesn't use a fence here so I guess that should work
	local h = dpdkc.read_reg32(id, addrh)
	local l = dpdkc.read_reg32(id, addrl)
	local h2 = dpdkc.read_reg32(id, addrh) -- check for overflow during read
	if h2 ~= h then
		-- overflow during the read
		-- we can just read the lower value again (1 overflow every 850ms max)
		l = dpdkc.read_reg32(self.id, 0x00300680)
		h = h2 -- use the new high value
	end
	local val = l + h * 2^32 -- 48 bits, double is fine
	local diff = val - last
	if diff < 0 then
		diff = 2^48 + diff
	end
	return diff, val
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

local lastGorc = 0
local lastUprc = 0
local lastMprc = 0
local lastBprc = 0

--- get the number of packets received since the last call to this function
function dev:getRxStats()
	local devId = self:getPciId()
	if devId == mod.PCI_ID_XL710 then
		local uprc, mprc, bprc, gorc
		uprc, lastUprc = readCtr32(self.id, 0x003005A0, lastUprc)
		mprc, lastMprc = readCtr32(self.id, 0x003005C0, lastMprc)
		bprc, lastBprc = readCtr32(self.id, 0x003005E0, lastBprc)
		gorc, lastGorc = readCtr48(self.id, 0x00300000, lastGorc)
		return uprc + mprc + bprc, gorc
	else
		return dpdkc.read_reg32(self.id, GPRC), dpdkc.read_reg32(self.id, GORCL) + dpdkc.read_reg32(self.id, GORCH) * 2^32
	end
end



local lastGotc = 0
local lastUptc = 0
local lastMptc = 0
local lastBptc = 0

function dev:getTxStats()
	local badPkts = tonumber(dpdkc.get_bad_pkts_sent(self.id))
	local badBytes = tonumber(dpdkc.get_bad_bytes_sent(self.id))
	-- FIXME: this should really be split up into separate functions/files
	local devId = self:getPciId()
	if devId == mod.PCI_ID_XL710 then
		local uptc, mptc, bptc, gotc
		uptc, lastUptc = readCtr32(self.id, 0x003009C0, lastUptc)
		mptc, lastMptc = readCtr32(self.id, 0x003009E0, lastMptc)
		bptc, lastBptc = readCtr32(self.id, 0x00300A00, lastBptc)
		gotc, lastGotc = readCtr48(self.id, 0x00300680, lastGotc)
		return uptc + mptc + bptc - badPkts, gotc - badBytes
	else
		-- TODO: check for ixgbe
		return dpdkc.read_reg32(self.id, GPTC) - badPkts, dpdkc.read_reg32(self.id, GOTCL) + dpdkc.read_reg32(self.id, GOTCH) * 2^32 - badBytes
	end
end


--- TODO: figure out how to actually acquire statistics in a meaningful way for dropped packets :/
function dev:getRxStatsAll()
	local stats = ffi.new("struct rte_eth_stats")
	dpdkc.rte_eth_stats_get(self.id, stats)
	return stats
end

local RTTDQSEL = 0x00004904

--- Set the tx rate of a queue in MBit/s.
--- This sets the payload rate, not to the actual wire rate, i.e. preamble, SFD, and IFG are ignored.
--- The X540 and 82599 chips seem to have a hardware bug (?): they seem use the wire rate in some point of the throttling process.
--- This causes erratic behavior for rates >= 64/84 * WireRate when using small packets.
--- The function is non-linear (not even monotonic) for such rates.
--- The function prints a warning if such a rate is configured.
--- A simple work-around for this is using two queues with 50% of the desired rate.
--- Note that this changes the inter-arrival times as the rate control of both queues is independent.
function txQueue:setRate(rate)
	if self.dev:getPciId() ~= mod.PCI_ID_82599 and self.dev:getPciId() ~= mod.PCI_ID_X540 and self.dev:getPciId() ~= mod.PCI_ID_X520 and self.dev:getPciId() ~= mod.PCI_ID_X520_T2 then

		log:fatal("TX rate control not yet implemented for this NIC")
	end
	local speed = self.dev:getLinkStatus().speed
	if speed <= 0 then
		log:warn("Link down, assuming 10 GbE connection")
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
		log:warn("Rates with a payload rate >= 64/84%% do not work properly with small packets due to a hardware bug, see documentation for details")
	end
	if rate <= 0 then
		log:fatal("Rate must be > 0")
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
	self.used = true
	dpdkc.send_all_packets(self.id, self.qid, bufs.array, bufs.size)
	return bufs.size
end

function txQueue:sendN(bufs, n)
	self.used = true
	dpdkc.send_all_packets(self.id, self.qid, bufs.array, n)
	return n
end

function txQueue:start()
	assert(dpdkc.rte_eth_dev_tx_queue_start(self.id, self.qid) == 0)
end

function txQueue:stop()
	assert(dpdkc.rte_eth_dev_tx_queue_stop(self.id, self.qid) == 0)
end

--- Send a single timestamped packet
-- @param bufs bufArray, only the first packet in it will be sent
-- @param offs offset in the packet at which the timestamp will be written. must be a multiple of 8
function txQueue:sendWithTimestamp(bufs, offs)
	self.used = true
	offs = offs and offs / 8 or 6 -- first 8-byte aligned value in UDP payload
	dpdkc.send_packet_with_timestamp(self.id, self.qid, bufs.array[0], offs)
end

do
	local mempool
	--- Send rate-controlled packets by filling gaps with invalid packets.
	-- @param bufs
	-- @param targetRate optional, hint to the driver which total rate you are trying to achieve.
	--   increases precision at low non-cbr rates
	-- @param method optional, defaults to "crc" (which is also the only one that is implemented)
	function txQueue:sendWithDelay(bufs, targetRate, method)
		targetRate = targetRate or 14.88
		self.used = true
		mempool = mempool or memory.createMemPool{
			func = function(buf)
				local pkt = buf:getTcpPacket()
				pkt:fill()
			end
		}
		method = method or "crc"
		local avgPacketSize = 1.25 / (targetRate * 2) * 1000
		local minPktSize
		-- allow smaller packets at low rates
		-- (15.6 mpps is the max the NIC can handle)
		-- TODO: move to device-specific code for i40e support
		if targetRate < 7.8 then
			minPktSize = 34
		else
			minPktSize = 76
		end
		if method == "crc" then
			dpdkc.send_all_packets_with_delay_bad_crc(self.id, self.qid, bufs.array, bufs.size, mempool, minPktSize)
		elseif method == "size" then
			dpdkc.send_all_packets_with_delay_invalid_size(self.id, self.qid, bufs.array, bufs.size, mempool)
		else
			log:fatal("Unknown delay method %s", method)
		end
		return bufs.size
	end
end

--- Restarts all tx queues that were actively used by this task.
--- 'Actively used' means that either :send() or :sendWithDelay() was called from the current task.
function mod.reclaimTxBuffers()
	for _, dev in pairs(devices) do
		for _, queue in pairs(dev.txQueues) do
			if queue.used then
				queue:stop()
				queue:start()
			end
		end
	end
end

--- Receive packets from a rx queue.
--- Returns as soon as at least one packet is available.
function rxQueue:recv(bufArray)
	while dpdk.running() do
		local rx = dpdkc.rte_eth_rx_burst_export(self.id, self.qid, bufArray.array, bufArray.size)
		if rx > 0 then
			return rx
		end
	end
	return 0
end

--- Receive packets from a rx queue and save timestamps in a separate array.
--- Returns as soon as at least one packet is available.
-- TODO: use the udata64 field in dpdk2.x
function rxQueue:recvWithTimestamps(bufArray, timestamps)
	return dpdkc.receive_with_timestamps_software(self.id, self.qid, bufArray.array, bufArray.size, timestamps)
end

function rxQueue:getMacAddr()
  return ffi.cast("union mac_address", ffi.C.rte_eth_macaddr_get(self.id))
end

function txQueue:getMacAddr()
  return ffi.cast("union mac_address", ffi.C.rte_eth_macaddr_get(self.id))
end

function rxQueue:recvAll(bufArray)
	log:fatal("NYI")
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

--- Receive packets from a rx queue with a timeout.
--- Does not perform a busy wait, this is not suitable for high-throughput applications.
function rxQueue:tryRecvIdle(bufArray, maxWait)
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
		dpdk.sleepMicrosIdle(1)
	end
	return 0
end

-- export prototypes to extend them in other modules (TODO: use a proper 'class' system with mix-ins or something)
mod.__devicePrototype = dev
mod.__txQueuePrototype = txQueue
mod.__rxQueuePrototype = rxQueue

return mod

