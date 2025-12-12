local mg		= require "moongen"
local memory	= require "memory"
local stats		= require "stats"

defaults = {rx_queues = 1, tx_queues = 0}

function task(taskNum, txInfo, rxInfo, args)
	local rxQ = rxInfo[1].queue
	local rxCtr = stats:newDevRxCounter(rxQ)
	local rx_buf = args.rx_buf
	if not rx_buf then rx_buf = 128 end
	local rxBufs = memory.bufArray(rx_buf)

	while mg.running() do
		local rx = rxQ:recv(rxBufs)
		rxBufs:freeAll()
		rxCtr:update()
	end
	rxCtr:finalize()
end

