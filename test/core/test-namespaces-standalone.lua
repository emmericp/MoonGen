local dpdk	= require "dpdk"
local ns	= require "namespaces"

local test1 = ns:get("test1")
local test2 = ns:get("test2")
local test3 = ns:get()

function master()
	assert(test1 == ns:get("test1"))
	assert(test2 == ns:get("test2"))
	assert(test3 ~= test and test3 ~= test2)
	test2.number = 5
	test2.string = "foo"
	test2.table = { hello = "world", { 1 } }
	for i = 1, 100 do
		test3[tostring(i)] = i
	end
	assert(test1.lock and test2.lock)
	assert(test1.lock ~= test2.lock)
	dpdk.launchLua("slave", test1, test2, test3):wait()
	assert(test3["66"] == 66) -- must not block
end

function slave(test1Arg, test2Arg, test3Arg)
	-- serializing should kill our namespaces
	assert(test1Arg == test1)
	assert(test2Arg == test2)
	assert(test3Arg == test3)
	assert(test2.number == 5)
	assert(test2.string == "foo")
	assert(test2.table[1][1] == 1)
	assert(test3.number == nil)
	local seen = {}
	test3:forEach(function(key, val) seen[key] = val end)
	for i = 1, 100 do
		assert(seen[tostring(i)] == i)
	end
	-- must release the lock properly
	local ok = pcall(test3.forEach, test3, function(key, val) error() end)
	assert(not ok)
end

