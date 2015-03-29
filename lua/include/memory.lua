local mod = {}

local ffi = require "ffi"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"

ffi.cdef [[
	void* malloc(size_t size);
	void free(void* buf);
]]

local C = ffi.C
local cast = ffi.cast

--- Off-heap allocation, not garbage-collected.
-- @param ctype a ffi type, must be a pointer or array type
-- @param size the amount of memory to allocate
function mod.alloc(ctype, size)
	return cast(ctype, C.malloc(size))
end

--- Free off-heap allocated object.
function mod.free(buf)
	C.free(buf)
end


--- Create a new memory pool.
-- @param n optional (default = 2047), size of the mempool
-- @param func optional, init func, called for each argument
-- @param socket optional (default = socket of the calling thread), NUMA association. This cannot be the only argument in the call.
-- @param bufSize optional the size of each buffer, can only be used if all other args are passed as well
function mod.createMemPool(n, func, socket, bufSize)
	if type(n) == "function" then -- (func[, socket])
		socket = func
		func = n
		n = nil
	elseif type(func) == "number" then -- (n[, socket])
		socket = func
		func = nil
	end
	n = n or 2047
	socket = socket or -1
	local mem = dpdkc.init_mem(n, socket, bufSize and bufSize or 0)
	if func then
		local bufs = {}
		for i = 1, n do
			local buf = mem:alloc(1522)
			func(buf)
			bufs[#bufs + 1] = buf
		end
		for i, v in ipairs(bufs) do
			dpdkc.rte_pktmbuf_free_export(v)
		end
	end
	return mem
end

local mempool = {}
mempool.__index = mempool

function mempool:alloc(l)
	local r = dpdkc.alloc_mbuf(self)
	r.pkt.pkt_len = l
	r.pkt.data_len = l
	return r
end

local bufArray = {}

--- Create a new array of memory buffers (initialized to nil).
function mempool:bufArray(n)
	n = n or 63
	return setmetatable({
		size = n,
		array = ffi.new("struct rte_mbuf*[?]", n),
		mem = self,
	}, bufArray)
end

do
	local function alloc()
		error("buf array not associated with a memory pool", 2)
	end
	
	--- Create a new array of memory buffers (initialized to nil).
	-- This buf array is not associated with a memory pool.
	function mod.createBufArray(n)
		-- allow self-calls
		if self == mod then
			n = self
		end
		n = n or 63
		return setmetatable({
			size = n,
			array = ffi.new("struct rte_mbuf*[?]", n),
			alloc = alloc
		}, bufArray)
	end

	mod.bufArray = mod.createBufArray
end

function bufArray:offloadUdpChecksums(ipv4, l2Len, l3Len)
	ipv4 = ipv4 == nil or ipv4
	l2_len = l2_len or 14
	if ipv4 then
		l3_len = l3_len or 20
		for i = 0, self.size - 1 do
			self.array[i].ol_flags = bit.bor(self.array[i].ol_flags, dpdk.PKT_TX_IPV4_CSUM, dpdk.PKT_TX_UDP_CKSUM)
			self.array[i].pkt.header_lengths = l2_len * 512 + l3_len
		end
		dpdkc.calc_ipv4_pseudo_header_checksums(self.array, self.size, 20)
	else 
		l3_len = l3_len or 40
		for i = 0, self.size - 1 do
			self.array[i].ol_flags = bit.bor(self.array[i].ol_flags, dpdk.PKT_TX_UDP_CKSUM)
			self.array[i].pkt.header_lengths = l2_len * 512 + l3_len
		end
		dpdkc.calc_ipv6_pseudo_header_checksums(self.array, self.size, 30)
	end
end

function bufArray:offloadIPChecksums(ipv4, l2Len, l3Len)
	ipv4 = ipv4 == nil or ipv4
	if ipv4 then
		l2_len = l2_len or 14
		l3_len = l3_len or 20
		for i = 0, self.size - 1 do
			self.array[i].ol_flags = bit.bor(self.array[i].ol_flags, dpdk.PKT_TX_IPV4_CSUM)
			self.array[i].pkt.header_lengths = l2_len * 512 + l3_len
		end
	end
end

function bufArray:offloadTcpChecksums(ipv4, l2Len, l3Len)
	ipv4 = ipv4 == nil or ipv4
	l2_len = l2_len or 14
	if ipv4 then
		l3_len = l3_len or 20
		for i = 0, self.size - 1 do
			self.array[i].ol_flags = bit.bor(self.array[i].ol_flags, dpdk.PKT_TX_IPV4_CSUM, dpdk.PKT_TX_TCP_CKSUM)
			self.array[i].pkt.header_lengths = l2_len * 512 + l3_len
		end
		dpdkc.calc_ipv4_pseudo_header_checksums(self.array, self.size, 25)
	else 
		l3_len = l3_len or 40
		for i = 0, self.size - 1 do
			self.array[i].ol_flags = bit.bor(self.array[i].ol_flags, dpdk.PKT_TX_TCP_CKSUM)
			self.array[i].pkt.header_lengths = l2_len * 512 + l3_len
		end
		dpdkc.calc_ipv6_pseudo_header_checksums(self.array, self.size, 35)
	end
end

--- Allocates buffers from the memory pool and fills the array
function bufArray:alloc(size)
	for i = 0, self.size - 1 do
		self.array[i] = self.mem:alloc(size)
	end
end

--- Free all buffers in the array. Stops when it encounters the first one that is null.
function bufArray:freeAll()
	for i = 0, self.size - 1 do
		if self.array[i] == nil then
			return
		end
		dpdkc.rte_pktmbuf_free_export(self.array[i])
		self.array[i] = nil
	end
end

--- Free the first n buffers.
function bufArray:free(n)
	for i = 0, n - 1 do
		if self.array[i] ~= nil then
			dpdkc.rte_pktmbuf_free_export(self.array[i])
		end
	end
end

function bufArray.__index(self, k)
	-- TODO: is this as fast as I hope it to be?
	return type(k) == "number" and self.array[k - 1] or bufArray[k]
end

function bufArray.__newindex(self, i, v)
	self.array[i - 1] = v
end

function bufArray.__len(self)
	return self.size
end

do
	local function it(self, i)
		if i >= self.size then
			return nil
		end
		return i + 1, self.array[i]
	end

	function bufArray.__ipairs(self)
		return it, self, 0
	end
end


ffi.metatype("struct mempool", mempool)

return mod

