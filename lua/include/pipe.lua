local mod = {}

local memory	= require "memory"
local ffi		= require "ffi"
local serpent	= require "Serpent"
local dpdk		= require "dpdk"

ffi.cdef [[
	// dummy
	struct spsc_ptr_queue { };

	struct spsc_ptr_queue* make_pipe();
	void enqueue(struct spsc_ptr_queue* queue, void* data);
	void* try_dequeue(struct spsc_ptr_queue* queue);
	void* peek(struct spsc_ptr_queue* queue);
	uint8_t pop(struct spsc_ptr_queue* queue);
	size_t count(struct spsc_ptr_queue* queue);
]]

local C = ffi.C


mod.slowPipe = {}
local slowPipe = mod.slowPipe
slowPipe.__index = slowPipe

--- Create a new slow pipe.
-- A pipe can only be used by exactly two tasks: a single reader and a single writer.
-- Slow pipes are called slow pipe because they are slow (duh).
-- Any objects passed to it will be *serialized* as strings.
-- This means that it supports arbitrary Lua objects following MoonGens usual serialization rules.
-- Use a 'fast pipe' if you need fast inter-task communication. Fast pipes are restricted to LuaJIT FFI objects.
function mod:newSlowPipe()
	return setmetatable({
		pipe = C.make_pipe()
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

function slowPipe:__serialize()
	return "require'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').slowPipe"), true
end


function mod:newFastPipe()
	error("NYI")
end

return mod

