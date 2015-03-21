-- TODO: find a proper testing library that actually works for our use case
package.path = package.path .. "lua/include/?.lua;lua/include/?/init.lua;lua/include/lib/?.lua;lua/include/lib/?/init.lua;../lua/include/?.lua;../lua/include/?/init.lua;../lua/include/lib/?.lua;../lua/include/lib/?/init.lua;../../lua/include/?.lua;../../lua/include/?/init.lua;../../lua/include/lib/?.lua;../../lua/include/lib/?/init.lua;"

MOONGEN_TASK_NAME = "master" -- to prevent device.lua from doing stupid things

local serpent = require "Serpent"
local ffi = require "ffi"
local device = require "device"

ffi.cdef [[
	struct testStruct {
		int a;
		int b;
	};
]]


local function ser(val)
	print("serializating " .. tostring(val) .. ":")
	local serialized = serpent.dump(val)
	print(serialized)
	local deserialized = loadstring(serialized)()
	return deserialized
end

local function assertSame(a, b)
	if a ~= b then 
		print(a, b)
	end
	assert(a == b)
end


local before, after

local cStruct = ffi.new("struct testStruct", { a = 5, b = 3 })
-- basic serialization of a value

before = { 1, cStruct, foo = { bar = cStruct } }
after = ser(before)

assertSame(before[1], after[1])
assertSame(before[2], after[2])
assertSame(before.foo.bar.b, after.foo.bar.b)

-- test serialization of pointers
before = after -- after is a pointer to the struct due to the previous serialization
after = ser(before)

assertSame(before[1], after[1])
assertSame(before[2], after[2])
assertSame(before.foo.bar.b, after.foo.bar.b)


before = device.get(0)
after = ser(before)

assertSame(before.id, after.id)
assertSame(getmetatable(before), getmetatable(after))


before = device.get(1):getRxQueue(2)
after = ser(before)

assertSame(before.id, after.id)
assertSame(before.qid, after.qid)
assertSame(getmetatable(before), getmetatable(after))


-- needs to be stubbed as it depends on DPDK and is called during deserialization
device.__txQueuePrototype.__index.getTxRate = function() end

before = device.get(1):getTxQueue(2)
after = ser(before)

assertSame(before.id, after.id)
assertSame(before.qid, after.qid)
assertSame(getmetatable(before), getmetatable(after))

















