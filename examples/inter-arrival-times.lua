local dpdk	= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local ts	= require "timestamping"
local dpdkc	= require "dpdkc"

local ffi	= require "ffi"

-- TODO: this does not work properly if the system receives packets before this script is started
-- this happens because the nic then receives frames before time stamping is enabled
-- a work-around could be emptying the rx queue once (e.g. by reading a certain amount of packets)
-- after startup
function master(...)
	local rxPort = tonumberall(...)
	if not rxPort then
		errorf("usage: rxPort")
	end
	rxDev = device.config(rxPort, memory.createMemPool())
	rxDev:wait()
	local queue = rxDev:getRxQueue(0)
	queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray(64)
	local times = {}
	while dpdk.running() do
		local n = queue:recv(bufs)
		for i = 1, n do
			local ts = bufs[i]:getTimestamp()
			times[#times + 1] = ts
		end
		total = total + n
		bufs:freeAll()
	end
	local pkts = rxDev:getRxStats(port)
	table.sort(times) -- TODO: why are we getting some packets OoO? this should be impossible...?
	-- TODO: create a class for histograms as this code is currently copied in a lot of examples...
	local hist = {}
	local last
	for i, v in ipairs(times) do
		if last then
			local diff = v - last
			hist[diff] = (hist[diff] or 0) + 1
		end
		last = v
		--print(v)
	end
	local sortedHist = {}
	for k, v in pairs(hist) do 
		table.insert(sortedHist,  { k = k, v = v })
	end
	local sum = 0
	local samples = 0
	table.sort(sortedHist, function(e1, e2) return e1.k < e2.k end)
	print("Histogram:")
	for _, v in ipairs(sortedHist) do
		sum = sum + v.k * v.v
		samples = samples + v.v
		print(v.k, v.v)
	end
	print()
	print("Average: " .. (sum / samples) .. " ns, " .. samples .. " samples")
	print("Lost packets: " .. pkts - total
		.. " (this can happen if the NIC still receives data after this script stops the receive loop)")
end


