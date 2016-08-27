local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local stats	 = require "stats"
local log    = require "log"

function configure(parser)
	parser:argument("rxDev", "The device to receive from"):convert(tonumber)
end

function master(args)
	local rxDev = device.config{port = args.rxDev, dropEnable = false}
	device.waitForLinks()
	mg.startTask("dumpSlave", rxDev:getRxQueue(0))
	mg.waitForTasks()
end


function dumpSlave(queue)
	local bufs = memory.bufArray()
	local pktCtr = stats:newPktRxCounter("Packets counted", "plain")
	while mg.running() do
		local rx = queue:tryRecv(bufs, 100)
		for i = 1, rx do
			local buf = bufs[i]
			buf:dump()
			pktCtr:countPacket(buf)
		end
		bufs:free(rx)
		pktCtr:update()
	end
	pktCtr:finalize()
end

