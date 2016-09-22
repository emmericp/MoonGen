--! @file rx-to-pcap.lua
--! @brief Capture to Pcap with software timestamping

local mg		= require "moongen"
local memory		= require "memory"
local device		= require "device"
local log		= require "log"
local ts 		= require "timestamping"
local pcap		= require "pcap"
local ffi		= require "ffi"
local stats		= require "stats"

function configure(parser)
	parser:description("Reads packets from device and writes them to pcap files.")
	parser:argument("dev", "Devices to receive from."):args("+"):convert(tonumber)
	parser:option("-s --sink", "File prefix to write pcap data: 'PREFIX-portNum-queueNum.pcap'")
	parser:option("-q --queues", "Number of RX queues."):default(1):convert(tonumber)
	parser:option("-m --maxp", "Reads at most maxp packets or forever if maxp == 0."):default(0):convert(tonumber)

end

function master(args)
	for i, dev in ipairs(args.dev) do
		local rxDev = device.config{ port = dev, rxQueues = args.queues }
		local maxp = args.maxp / args.queues
		rxDev:wait()
		for i = 0, args.queues-1 do
			local sink = args.sink and args.sink..dev..'-'..i..'.pcap'
			mg.startTask("pcapSinkSlave", rxDev:getRxQueue(i), sink, maxp)
		end
	end

	mg.waitForTasks()
end



--! @brief: receive and store packets with software timestamps
function pcapSinkSlave(queue, sink, maxp)
	print('pcapSinkSlave is running')
	local numbufs = (maxp == 0) and 100 or math.min(100, maxp)
	local bufs = memory.bufArray(numbufs)

	local pcapSinkWriter = sink and pcapWriter:newPcapWriter(sink)
	local ctr = stats:newDevRxCounter(queue, "plain")
	local pkts = 0
	while mg.running() and (maxp == 0 or pkts < maxp) do
		local rxnum = (maxp == 0) and #bufs or math.min(#bufs, maxp - pkts)
		local rx = queue:recvWithTimestamps(bufs, rxnum)
		if pcapSinkWriter and rx > 0 then
			pcapSinkWriter:writeTSC(bufs, bufs, rx, true)
		end
		pkts = pkts + rx
		ctr:update()
		bufs:free(rx)
	end
	print('pcapSinkSlave terminated after receiving '..pkts.." packets")
	bufs:freeAll()

	ctr:finalize()
	if pcapSinkWriter then
		pcapSinkWriter:close()
	end
end
