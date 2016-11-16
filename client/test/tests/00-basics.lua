--  Basic functionality: threads and message-passing
local lunit		= require "luaunit"
local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local timer		= require "timer"

local log		= require "testlog"
local testlib	= require "testlib"
local tconfig	= require "tconfig"

local ffi		= require "ffi"

ffi.cdef[[
	typedef struct teststruct {
		double value1;
		uint64_t value2;
	} teststruct_t;

]]

function master()
	log:info( "Function to test: Threads and message-passing" )
	local foo = memory.alloc("teststruct_t*", ffi.sizeof("teststruct_t"))
	foo.value1 = -0.25
	foo.value2 = 0xDEADBEEFDEADBEEFULL
	dpdk.launchLua("slave1", 1, "string"):wait()
	dpdk.launchLua("slave2", {1, { foo = "bar", cheese = 5 }}):wait()
	dpdk.launchLua("slave3", foo):wait()
end

function slave1(num, str)
	lunit.assertEquals(num, 1)
	lunit.assertEquals(str, "string")
end

function slave2(arg)
	lunit.assertEquals(arg, {1, {foo = "bar", cheese = 5}})
end

function slave3(arg)
	lunit.assertEquals(arg.value1, -0.25)
	lunit.assertEquals(arg.value2, 0xDEADBEEFDEADBEEFULL)
end


