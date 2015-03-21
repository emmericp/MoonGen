-- TODO: this is completely broken for some reason :(

local dpdk		= require "dpdk"
local dpdkc		= require "dpdkc"

describe("task management", function()
	it("should recycle cores", function()
		for i = 1, 500 do
			dpdk.launchLua("emptyTask")
			dpdk.sleepMillis(100)
		end
	end)
	it("should serialize simple arguments", function()
		local task = dpdk.launchLua("passThroughTask", 1, 2, 3)
		local a, b, c = task:wait()
		assert.equals(a, 1)
		assert.equals(b, 2)
		assert.equals(c, 3)
		local task = dpdk.launchLua("passThroughTask", false, "foo")
		local a, b, c = task:wait()
		assert.equals(a, false)
		assert.equals(b, "foo")
		assert.equals(c, nil)
	end)
	it("should serialize tables", function()
		local task = dpdk.launchLua("passThroughTask", { foo = "bar", x = 1 })
		local tbl = task:wait()
		assert.are.same(tbl, { foo = "bar", x = 1 })
	end)
end)

function emptyTask()
end

function passThroughTask(...)
	return ...
end

