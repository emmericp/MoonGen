local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts		= require "timestamping"
local hist		= require "histogram"
local log		= require "log"
local timer		= require "timer"

function master(rxPort, waitTime)
	if not rxPort then
		errorf("usage: rxPort [waitTime]")
	end
	rxDev = device.config{ port = rxPort, rxDescs = 4096, dropEnable = false }
	rxDev:wait()
	local queue = rxDev:getRxQueue(0)
	queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray()
	local times = {}
	local timer = timer:new(waitTime)
	while dpdk.running() do
		local n = queue:recv(bufs)
		for i = 1, n do
			if timer:expired() then
				local ts = bufs[i]:getTimestamp()
				times[#times + 1] = ts
			end
		end
		total = total + n
		bufs:free(n)
	end
	local pkts = rxDev:getRxStats(port)
	local h = hist:create()
	local last
	for i, v in ipairs(times) do
		if last then
			local diff = v - last
			h:update(diff)
		end
		last = v
	end
	h:print()
	h:save("histogram.csv")
	log[(pkts - total > 0 and "warn" or "info")](log, "Lost packets: " .. pkts - total
		.. " (this can happen if the NIC still receives data after this script stops the receive loop)")
end


