local mod = {}

local ffi = require "ffi"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local dev = require "device"


function mod.createMemPool(n, func)
	return mod.createMemPoolOnSocket(n, -1)
end

--- Create a new memory pool.
-- @param n optional (default = 2047), size of the mempool
-- @param func optional, init func, called for each argument
-- @param socket optional (default = socket of the calling thread), NUMA association. This cannot be the only argument in the call.
function mod.createMemPool(n, func, socket)
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
	local mem = dpdkc.init_mem(n, socket)
	if func then
		local bufs = {}
		for i = 1, n do
			local buf = mem:alloc(1518)
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
	return setmetatable({
		size = n,
		array = ffi.new("struct rte_mbuf*[?]", n),
		mem = self,
	}, bufArray)
end

do
	local function fill()
		error("buf array not associated with a memory pool", 2)
	end
	
	--- Create a new array of memory buffers (initialized to nil).
	-- This buf array is not associated with a memory pool.
	function mod.createBufArray(n)
		return setmetatable({
			size = n,
			array = ffi.new("struct rte_mbuf*[?]", n),
			fill = fill
		}, bufArray)
	end
end

--- Allocates buffers from the memory pool and fills the array
function bufArray:fill(size)
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

-- TODO: enable Lua 5.2 in luajit and add __len and __ipairs

ffi.metatype("struct mempool", mempool)

return mod

