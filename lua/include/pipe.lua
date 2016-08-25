---------------------------------
--- @file pipe.lua
--- @brief Pipe ...
--- @todo TODO docu
---------------------------------

local mod = {}

local memory	= require "memory"
local ffi		= require "ffi"
local serpent	= require "Serpent"
local dpdk		= require "dpdk"
local log		= require "log"

ffi.cdef [[
	// dummy
	struct spsc_ptr_queue { };

	struct spsc_ptr_queue* make_pipe(int size);
	void enqueue(struct spsc_ptr_queue* queue, void* data);
	uint8_t try_enqueue(struct spsc_ptr_queue* queue, void* data);
	void* try_dequeue(struct spsc_ptr_queue* queue);
	void* peek(struct spsc_ptr_queue* queue);
	uint8_t pop(struct spsc_ptr_queue* queue);
	size_t count(struct spsc_ptr_queue* queue);
	
	// DPDK SPSC ring
	struct rte_ring { };
	struct rte_ring* create_ring(uint32_t count, int32_t socket);
	int ring_enqueue(struct rte_ring* r, struct rte_mbuf** obj, int n);
	int ring_dequeue(struct rte_ring* r, struct rte_mbuf** obj, int n);
]]

local C = ffi.C

mod.packetRing = {}
local packetRing = mod.packetRing
packetRing.__index = packetRing

function mod:newPacketRing(size, socket)
	size = size or 8192
	socket = socket or -1
	return setmetatable({
		ring = C.create_ring(size, socket)
	}, packetRing)
end

function mod:newPacketRingFromRing(ring)
	return setmetatable({
		ring = ring
	}, packetRing)
end

-- FIXME: this is work-around for some bug with the serialization of nested objects
function mod:sendToPacketRing(ring, bufs)
	C.ring_enqueue(ring, bufs.array, bufs.size);
end

function packetRing:send(bufs)
	C.ring_enqueue(self.ring, bufs.array, bufs.size);
end

function packetRing:sendN(bufs, n)
	C.ring_enqueue(self.ring, bufs.array, n);
end

function packetRing:recv(bufs)
	error("NYI")
end

function packetRing:__serialize()
	return "require'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').packetRing"), true
end

mod.slowPipe = {}
local slowPipe = mod.slowPipe
slowPipe.__index = slowPipe

--- Create a new slow pipe.
--- A pipe can only be used by exactly two tasks: a single reader and a single writer.
--- Slow pipes are called slow pipe because they are slow (duh).
--- Any objects passed to it will be *serialized* as strings.
--- This means that it supports arbitrary Lua objects following MoonGens usual serialization rules.
--- Use a 'fast pipe' if you need fast inter-task communication. Fast pipes are restricted to LuaJIT FFI objects.
function mod:newSlowPipe()
	return setmetatable({
		pipe = C.make_pipe(512)
	}, slowPipe)
end

function slowPipe:send(...)
	local vals = serpent.dump({ ... })
	local buf = memory.alloc("char*", #vals + 1)
	ffi.copy(buf, vals)
	C.enqueue(self.pipe, buf)
end

function slowPipe:tryRecv(wait)
	while wait >= 0 do
		local buf = C.try_dequeue(self.pipe)
		if buf ~= nil then
			local result = loadstring(ffi.string(buf))()
			memory.free(buf)
			return unpackAll(result)
		end
		wait = wait - 10
		if wait < 0 then
			break
		end
		dpdk.sleepMicros(10)
	end
end

function slowPipe:recv()
	local function loop(...)
		if not ... then
			return loop(self:tryRecv(10))
		else
			return ...
		end
	end
	return loop()
end

function slowPipe:count()
	return tonumber(C.count(self.pipe))
end

function slowPipe:__serialize()
	return "require'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').slowPipe"), true
end


mod.fastPipe = {}
local fastPipe = mod.fastPipe
fastPipe.__index = fastPipe

--- Create a new fast pipe.
--- A pipe can only be used by exactly two tasks: a single reader and a single writer.
--- Fast pipes are fast, but only accept FFI cdata pointers and nothing else.
--- Use a slow pipe to pass arbitrary objects.
function mod:newFastPipe(size)
	return setmetatable({
		pipe = C.make_pipe(size or 512)
	}, fastPipe)
end

function fastPipe:send(obj)
	C.enqueue(self.pipe, obj)
end

function fastPipe:trySend(obj)
	return C.try_enqueue(self.pipe, obj) ~= 0
end

-- FIXME: this is work-around for some bug with the serialization of nested objects
function mod:sendToFastPipe(pipe, obj)
	return C.try_enqueue(pipe, obj) ~= 0
end

function fastPipe:tryRecv(wait)
	while wait >= 0 do
		local buf = C.try_dequeue(self.pipe)
		if buf ~= nil then
			return buf
		end
		wait = wait - 10
		if wait < 0 then
			break
		end
		dpdk.sleepMicros(10)
	end
end

function fastPipe:recv()
	local function loop(...)
		if not ... then
			return loop(self:tryRecv(10))
		else
			return ...
		end
	end
	return loop()
end

function fastPipe:count()
	return tonumber(C.count(self.pipe))
end

function fastPipe:__serialize()
	return "require'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').fastPipe"), true
end

return mod

