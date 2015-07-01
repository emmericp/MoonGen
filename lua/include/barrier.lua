local mod = {}

local ffi = require "ffi"


ffi.cdef [[
    struct barrier { };
    struct barrier* make_barrier(size_t n);
    void barrier_wait(struct barrier* barrier);
	void barrier_reinit(struct barrier* barrier, size_t n);
]]

local C = ffi.C

local barrier = {}
barrier.__index = barrier


function mod.new(n)
    return C.make_barrier(n)
end

function barrier:wait()
    C.barrier_wait(self)
end

-- only call if NO threads are waiting on this barrier
function barrier:reinit(n)
    C.barrier_reinit(self, n)
end

ffi.metatype("struct barrier", barrier)

return mod
