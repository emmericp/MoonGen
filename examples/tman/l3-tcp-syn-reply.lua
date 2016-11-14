local mg		= require "moongen"
local memory	= require "memory"
local stats		= require "stats"
local log		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"

defaults = {rx_queues = 1, tx_queues = 1}

function configure(parser)
	parser:description("Depending on mode performs 2nd either 3rd step in 3-way TCP handshake")
	parser:command("SYNACK SYN+ACK synack 2", "Reply SYN -> SYN+ACK, i.e. perform the 2nd step of TCP handshake")
	parser:command("ACK ack 3", "Reply SYN+ACK -> ACK, i.e. perform the 3nd step of TCP handshake")
end

local zero16 = hton16(0)

function task(taskNum, txInfo, rxInfo, args)
	local txQ, rxQ = txInfo[1].queue, rxInfo[1].queue
	local synack = args.SYNACK
	if synack then
		print("Running in SYN+ACK mode")
	else
		print("Running in ACK mode")
	end
	local txBufs = memory.bufArray(tx_buf)
	local rxBufs = memory.bufArray(rx_buf)
	local txStats = stats:newDevTxCounter(txQ, "plain")
	local rxStats = stats:newDevRxCounter(rxQ, "plain")

	while mg.running() do
		local tx = 0
		local rx = rxQ:recv(rxBufs)
		for i = 1, rx do
			local buf = rxBufs[i]
			-- alter buf
			local pkt = buf:getTcpPacket(ipv4)
			if pkt.ip4:getProtocol() == ip4.PROTO_TCP and
				pkt.tcp:getSyn() and
				(pkt.tcp:getAck() or synack)
			then
				-- print(string.format("RECV %d %d\n", rx, tx))
				local seq = pkt.tcp:getSeqNumber()
				local ack = pkt.tcp:getAckNumber()

				if synack then
					pkt.tcp:setAck()
					pkt.tcp:setAckNumber(seq+1)
					pkt.tcp:setSeqNumber(ack)
				else
					pkt.tcp:unsetSyn()
					pkt.tcp:setAckNumber(seq+1)
					pkt.tcp:setSeqNumber(ack)
				end

				local tmp = pkt.ip4.src:get()
				pkt.ip4.src:set(pkt.ip4.dst:get())
				pkt.ip4.dst:set(tmp)

				local tmp1 = pkt.eth.dst:get()
				pkt.eth.dst:set(pkt.eth.src:get())
				pkt.eth.src:set(tmp1)

				local tmp2 = pkt.tcp:getDstPort()
				pkt.tcp:setDstPort(pkt.tcp:getSrcPort())
				pkt.tcp:setSrcPort(tmp2)

				--pkt.ip4:setChecksum(0)
				pkt.ip4.cs = zero16 -- FIXME: setChecksum() is extremely slow

				tx = tx + 1
				txBufs[tx] = buf
			end
		end
		rxBufs:freeAfter(rx)
		if tx > 0 then
			txBufs:resize(tx)
			--offload checksums to NIC
			txBufs:offloadTcpChecksums(ipv4)
			txQ:send(txBufs)

			rxStats:update()
			txStats:update()
		end
	end
	rxStats:finalize()
	txStats:finalize()
end
