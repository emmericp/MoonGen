-- vim:ts=4:sw=4:noexpandtab
local mod = {}

local ffi	= require "ffi"
local dpdkc = require "dpdkc"
local dpdk	= require "dpdk"
local ns	= require "namespaces"
local serpent = require "Serpent"

ffi.cdef [[
	void* malloc(size_t size);
	void free(void* buf);
	void* alloc_huge(size_t size);
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

--- Off-heap allocation on huge pages, not garbage-collected.
-- See memory.alloc.
-- TODO: add a free function for this
function mod.allocHuge(ctype, size)
	return cast(ctype, C.alloc_huge(size))
end

local mempools = {}
local mempoolCache = ns:get()

local cacheEnabled = false

--- Enable mempool recycling.
-- Calling this function enables the mempool cache. This prevents memory leaks
-- as DPDK cannot delete mempools.
-- Mempools with the same parameters created on the same core will be recycled.
-- This is not yet enabled by default because I'm not 100% confident that it works
-- properly in all cases.
-- For example, mempools passed to other tasks will probably break stuff.
function mod.enableCache()
	cacheEnabled = true
end

local function getPoolFromCache(socket, n, bufSize)
	if not cacheEnabled then
		return
	end
	local pool
	mempoolCache.lock(function()
		-- TODO: pass an iterator context to the callback
		-- the context could then run functions like abort() or removeCurrent()
		local result
		mempoolCache:forEach(function(key, pool)
			if result then
				return
			end
			if pool.socket == socket
			and	pool.n == n
			and pool.bufSize == bufSize
			and pool.core == dpdk.getCore() then
				result = key
			end
		end)
		if result then
			pool = mempoolCache[result].pool
			mempoolCache[result] = nil
		end
	end)
	if pool then
		local bufs = {}
		for i = 1, n do
			local buf = pool:alloc(bufSize)
			ffi.fill(buf.data, buf.len, 0)
			bufs[#bufs + 1] = buf
		end
		for _, v in ipairs(bufs) do
			dpdkc.rte_pktmbuf_free_export(v)
		end
	end
	return pool
end

--- Create a new memory pool.
-- Memory pools are recycled once the owning task terminates.
-- Call :retain() for mempools that are passed to other tasks.
-- A table with named arguments should be used.
-- @param args A table containing the following named arguments
--	n optional (default = 2047), size of the mempool
--	func optional, init func, called for each argument
-- 	socket optional (default = socket of the calling thread), NUMA association. This cannot be the only argument in the call.
-- 	bufSize optional the size of each buffer, can only be used if all other args are passed as well
function mod.createMemPool(...)
	local args = {...}
	if type(args[1]) == "table" then
	  args = args[1]
	else
	  --print "[WARNING] You are using a depreciated method for calling createMemPool(...). createMemPool(...) should be used with named arguments."
      if type(args[1]) == "function" then
	    -- (func[, socket])
	    args.socket = args[2]
        args.func = args[1]
      elseif type(args[2]) == "number" then
        -- (n[, socket])
        args.socket = args[2]
	  end
	end
	-- DPDK recommends to use a value of n=2^k - 1 here
	args.n = args.n or 2047
	args.socket = args.socket or select(2, dpdk.getCore())
	args.bufSize = args.bufSize or 2048
	-- TODO: get cached mempool from the mempool pool if possible and use that instead
	-- FIXME: the todo seems to be already implemented here.
	local mem = getPoolFromCache(args.socket, args.n, args.bufSize) or dpdkc.init_mem(args.n, args.socket, args.bufSize)
	if args.func then
		local bufs = {}
		for i = 1, args.n do
			-- TODO: make this dependent on bufSize
			local buf = mem:alloc(1522)
			args.func(buf)
			bufs[#bufs + 1] = buf
		end
		for i, v in ipairs(bufs) do
			dpdkc.rte_pktmbuf_free_export(v)
		end
	end
	mempools[#mempools + 1] = {
		pool = mem,
		socket = args.socket,
		n = args.n,
		bufSize = args.bufSize,
		core = dpdk.getCore()
	}
	return mem
end

--- Free all memory pools owned by this task.
-- All queues using these pools must be stopped before calling this.
function mod.freeMemPools()
	if not cacheEnabled then
		return
	end
	for _, mem in ipairs(mempools) do
		mempoolCache[tostring(mem.pool)] = mem
	end
	mempools = {}
end

local mempool = {}
mempool.__index = mempool

--- Retain a memory pool.
-- This will prevent the pool from being returned to a pool of pools once the task ends.
function mempool:retain()
	for i, v in ipairs(mempools) do
		if v.pool == self then
			table.remove(mempools, i)
			return
		end
	end
end

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

--- If called, IP chksum offloading will be done for the first n packets
--	in the bufArray.
--	@param ipv4 optional (default = true) specifies, if the buffers contain ipv4 packets
--	@param l2Len optional (default = 14)
--	@param l3Len optional (default = 20)
--	@param n optional (default = bufArray.size) for how many packets in the array, the operation
--	  should be applied
function bufArray:offloadIPChecksums(ipv4, l2Len, l3Len, n)
	-- please do not touch this function without carefully measuring the performance impact
	-- FIXME: touched this.
	--	added parameter n
	ipv4 = ipv4 == nil or ipv4
	n = n or self.size
	if ipv4 then
		l2_len = l2_len or 14
		l3_len = l3_len or 20
		for i = 0, n - 1 do
			local buf = self.array[i]
			buf.ol_flags = bit.bor(buf.ol_flags, dpdk.PKT_TX_IPV4_CSUM)
			buf.pkt.header_lengths = l2_len * 512 + l3_len
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
	dpdkc.alloc_mbufs(self.mem, self.array, self.size, size)
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

