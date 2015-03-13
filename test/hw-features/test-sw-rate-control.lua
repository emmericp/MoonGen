local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"
local filter	= require "filter"
local pkt	= require "packet"

describe("software rate control", function()
	local dev = device.config(5, memory.createMemPool())
	dev:wait()
	it("send bad MACs", function()
		local queue = dev:getTxQueue(0)
		local mem = memory.createMemPool()
		local bufs = mem:bufArray(511)
		local delays = {}
		for i = 1, 511 do
			delays[i] = 1500
		end
		local sent = 0
		local start = dpdk.getTime()
		while sent < 10^6 and dpdk.running() do
			bufs:alloc()
			sent = sent + queue:sendWithDelay(bufs, delays)
		end
		local time = dpdk.getTime() - start
		print(time)
		-- expected: 1.2864
		assert.is_true(time > 1.28)
		assert.is_true(time < 1.4)
	end)

end)
