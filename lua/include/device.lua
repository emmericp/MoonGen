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
mod.PCI_ID_X710		= 0x80861572
mod.PCI_ID_XL710	= 0x80861583
mod.PCI_ID_XL710Q1	= 0x80861584

mod.PCI_ID_82599_VF	= 0x808610ed
mod.PCI_ID_VIRTIO	= 0x1af41000

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
---    rxQueues number rssBaseQueue to (rssBaseQueue + rssNQueues - 1).
---    Use a power of two to achieve a better distribution.
---   rssBaseQueue optional (default = 0) The first queue to use for RSS
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
---   stripVlan (default = true) Strip the VLAN tag on the NIC.
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
	if args.stripVlan == nil then
		args.stripVlan = true
	end
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
	local pciId = dpdkc.get_pci_id(args.port)
	-- FIXME: this is stupid and should be fixed in DPDK
	local isi40e = pciId == mod.PCI_ID_XL710
	            or pciId == mod.PCI_ID_X710
	            or pciId == mod.PCI_ID_XL710Q1
	-- TODO: support options
	local disablePadding = pciId == mod.PCI_ID_X540
	                    or pciId == mod.PCI_ID_X520
	                    or pciId == mod.PCI_ID_X520_T2
	                    or pciId == mod.PCI_ID_82599
	local rc = dpdkc.configure_device(args.port, args.rxQueues, args.txQueues, args.rxDescs, args.txDescs, args.speed, args.mempool, args.dropEnable, rss_enabled, rss_hash_mask, args.disableOffloads or false, isi40e, args.stripVlan, disablePadding)
	if rc ~= 0 then
	    log:fatal("Could not configure device %d: error %d", args.port, rc)
	end
	local dev = mod.get(args.port)
	dev.initialized = true
	if rss_enabled == 1 then
		dev:setRssNQueues(args.rssNQueues, args.rssBaseQueue)
	end
	dev:setPromisc(true)
	return dev
end

ffi.cdef[[
struct rte_eth_rss_reta_entry64 {
	uint64_t mask;
	uint16_t reta[64];
};

int rte_eth_dev_rss_reta_update(uint8_t port, struct rte_eth_rss_reta_entry64* reta_conf, uint16_t reta_size);
uint16_t get_reta_size(int port);
]]

--- Setup RSS RETA table.
function dev:setRssNQueues(n, baseQueue)
	baseQueue = baseQueue or 0
	assert(n > 0)
	if bit.band(n, n - 1) ~= 0 then
		log:warn("RSS distribution to queues will not be fair as the number of queues (%d) is not a power of two.", n)
	end
	local retaSize = ffi.C.get_reta_size(self.id)
	if retaSize % 64 ~= 0 then
		log:fatal("NYI: number of RETA entries is not a multiple of 64", retaSize)
	end
	local entries = ffi.new("struct rte_eth_rss_reta_entry64[?]", retaSize / 64)
	local queue = baseQueue
	for i = 0, retaSize / 64 - 1 do
		entries[i].mask = 0xFFFFFFFFFFFFFFFFULL
		for j = 0, 63 do
			entries[i].reta[j] = queue
			queue = queue + 1
			if queue == baseQueue + n then
				queue = baseQueue
			end
		end
	end
	local ret = ffi.C.rte_eth_dev_rss_reta_update(self.id, entries, retaSize)
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
	[mod.PCI_ID_X710]	= "Intel Corporation Ethernet 10G 2P X710 Adapter",
	[mod.PCI_ID_XL710]	= "Ethernet Controller LX710 for 40GbE QSFP+",
	[mod.PCI_ID_XL710Q1]	= "Ethernet Converged Network Adapter XL710-Q1",
	[mod.PCI_ID_82599_VF]	= "Intel Corporation 82599 Ethernet Controller Virtual Function",
	[mod.PCI_ID_VIRTIO]	= "Virtio network device"
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
		l = dpdkc.read_reg32(self.id, addrl)
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


-- stupid XL710 NICs
local lastGorc = {}
local lastUprc = {}
local lastMprc = {}
local lastBprc = {}
local lastGotc = {}
local lastUptc = {}
local lastMptc = {}
local lastBptc = {}

-- required when using multiple ports from a single thread
for i = 0, dpdkc.get_max_ports() - 1 do
	lastGorc[i] = 0
	lastUprc[i] = 0
	lastMprc[i] = 0
	lastBprc[i] = 0
	lastGotc[i] = 0
	lastUptc[i] = 0
	lastMptc[i] = 0
	lastBptc[i] = 0
end

local GLPRT_UPRCL = {}
local GLPRT_MPRCL = {}
local GLPRT_BPRCL = {}
local GLPRT_GORCL = {}
local GLPRT_UPTCL = {}
local GLPRT_MPTCL = {}
local GLPRT_BPTCL = {}
local GLPRT_GOTCL = {}
for i = 0, 3 do
	GLPRT_UPRCL[i] = 0x003005A0 + 0x8 * i
	GLPRT_MPRCL[i] = 0x003005C0 + 0x8 * i
	GLPRT_BPRCL[i] = 0x003005E0 + 0x8 * i
	GLPRT_GORCL[i] = 0x00300000 + 0x8 * i
	GLPRT_UPTCL[i] = 0x003009C0 + 0x8 * i
	GLPRT_MPTCL[i] = 0x003009E0 + 0x8 * i
	GLPRT_BPTCL[i] = 0x00300A00 + 0x8 * i
	GLPRT_GOTCL[i] = 0x00300680 + 0x8 * i
end

--- get the number of packets received since the last call to this function
function dev:getRxStats()
	local devId = self:getPciId()
	if devId == mod.PCI_ID_XL710 or devId == mod.PCI_ID_X710 or devId == mod.PCI_ID_XL710Q1 then
		local uprc, mprc, bprc, gorc
		-- TODO: is this always correct?
		-- I guess it fails on VFs :/
		local port = dpdkc.get_pci_function(self.id)
		uprc, lastUprc[self.id] = readCtr32(self.id, GLPRT_UPRCL[port], lastUprc[self.id])
		mprc, lastMprc[self.id] = readCtr32(self.id, GLPRT_MPRCL[port], lastMprc[self.id])
		bprc, lastBprc[self.id] = readCtr32(self.id, GLPRT_BPRCL[port], lastBprc[self.id])
		gorc, lastGorc[self.id] = readCtr48(self.id, GLPRT_GORCL[port], lastGorc[self.id])
		return uprc + mprc + bprc, gorc
	elseif devId == mod.PCI_ID_82599 or devId == mod.PCI_ID_X540 or devId == mod.PCI_ID_X520 or devId == mod.PCI_ID_X520_T2 then
		return dpdkc.read_reg32(self.id, GPRC), dpdkc.read_reg32(self.id, GORCL) + dpdkc.read_reg32(self.id, GORCH) * 2^32
	else
		return 0, 0
	end
end


function dev:getTxStats()
	local badPkts = tonumber(dpdkc.get_bad_pkts_sent(self.id))
	local badBytes = tonumber(dpdkc.get_bad_bytes_sent(self.id))
	-- FIXME: this should really be split up into separate functions/files
	local devId = self:getPciId()
	if devId == mod.PCI_ID_XL710 or devId == mod.PCI_ID_X710 or devId == mod.PCI_ID_XL710Q1 then
		local uptc, mptc, bptc, gotc
		local port = dpdkc.get_pci_function(self.id)
		uptc, lastUptc[self.id] = readCtr32(self.id, GLPRT_UPTCL[port], lastUptc[self.id])
		mptc, lastMptc[self.id] = readCtr32(self.id, GLPRT_MPTCL[port], lastMptc[self.id])
		bptc, lastBptc[self.id] = readCtr32(self.id, GLPRT_BPTCL[port], lastBptc[self.id])
		gotc, lastGotc[self.id] = readCtr48(self.id, GLPRT_GOTCL[port], lastGotc[self.id])
		return uptc + mptc + bptc - badPkts, gotc - badBytes
	elseif devId == mod.PCI_ID_82599 or devId == mod.PCI_ID_X540 or devId == mod.PCI_ID_X520 or devId == mod.PCI_ID_X520_T2 then
		return dpdkc.read_reg32(self.id, GPTC) - badPkts, dpdkc.read_reg32(self.id, GOTCL) + dpdkc.read_reg32(self.id, GOTCH) * 2^32 - badBytes
	else
		return 0, 0
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
	local id = self.dev:getPciId()
	local dev = self.dev
	if id == mod.PCI_ID_X710 or id == mod.PCI_ID_XL710 or id == mod.PCI_ID_XL710Q1 then
		-- obviously fails if doing that from multiple threads; but you shouldn't do that anways
		dev.totalRate = dev.totalRate or 0
		dev.totalRate = dev.totalRate + rate
		log:warn("Per-queue rate limit NYI on this device, setting per-device rate limit to %d instead", dev.totalRate)
		self.dev:setRate(dev.totalRate)
		return
	end
	if id ~= mod.PCI_ID_82599 and id ~= mod.PCI_ID_X540 and id ~= mod.PCI_ID_X520 and id ~= mod.PCI_ID_X520_T2 then
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
	local id = self.dev:getPciId()
	if id ~= mod.PCI_ID_82599 and id ~= mod.PCI_ID_X540 and id ~= mod.PCI_ID_X520 and id ~= mod.PCI_ID_X520_T2 then
		return 0
	end
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

ffi.cdef[[
int i40e_aq_config_vsi_bw_limit(void *hw, uint16_t seid, uint16_t credit, uint8_t max_bw, struct i40e_asq_cmd_details *cmd_details);
]]

--- Set the maximum rate by all queues in Mbit/s.
--- Only supported on XL710 NICs.
--- Note: these NICs use packet size excluding CRC checksum unlike the ixgbe-style NICs.
--- This means you will get an unexpectedly high rate.
function dev:setRate(rate)
	-- we cannot calculate the "proper" rate here as we do not know the packet size
	rate = math.floor(rate / 50 + 0.5) -- 50mbit granularity
	local i40eDev = dpdkc.get_i40e_dev(self.id)
	local vsiSeid = dpdkc.get_i40e_vsi_seid(self.id)
	assert(ffi.C.i40e_aq_config_vsi_bw_limit(i40eDev, vsiSeid, rate, 0, nil) == 0)
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
	-- @param n optional, number of packets to send (defaults to full bufs)
	function txQueue:sendWithDelay(bufs, targetRate, method, n)
		targetRate = targetRate or 14.88
		self.used = true
		mempool = mempool or memory.createMemPool{
			func = function(buf)
				local pkt = buf:getTcpPacket()
				pkt:fill()
			end
		}
		method = method or "crc"
		n = n or bufs.size
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
			dpdkc.send_all_packets_with_delay_bad_crc(self.id, self.qid, bufs.array, n, mempool, minPktSize)
		elseif method == "size" then
			dpdkc.send_all_packets_with_delay_invalid_size(self.id, self.qid, bufs.array, n, mempool)
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
function rxQueue:recv(bufArray, numpkts)
	numpkts = numpkts or bufArray.size
	while dpdk.running() do
		local rx = dpdkc.rte_eth_rx_burst_export(self.id, self.qid, bufArray.array, math.min(bufArray.size, numpkts))
		if rx > 0 then
			return rx
		end
	end
	return 0
end

--- Receive packets from a rx queue and save timestamps in a separate array.
--- Returns as soon as at least one packet is available.
-- TODO: use the udata64 field in dpdk2.x
function rxQueue:recvWithTimestamps(bufArray, timestamps, numpkts)
	numpkts = numpkts or bufArray.size
	return dpdkc.receive_with_timestamps_software(self.id, self.qid, bufArray.array, math.min(bufArray.size, numpkts), timestamps)
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

