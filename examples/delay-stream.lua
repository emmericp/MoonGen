local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log 		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"
local dpdkc     = require "dpdkc"


-- non-blocking version of rxQueue:recv()
local function recv_nb(rxQ, bufArray)
	return dpdkc.rte_eth_rx_burst_export(rxQ.id, rxQ.qid, bufArray.array, bufArray.size)
end

function configure(parser)
    -- do nothing, just check parse errors
	function convertMac_fake(str)
		mac = parseMacAddress(str, true)
		if not mac then
			parser:error("failed to parse MAC "..str)
		end
		return str
	end

	function convertTime(str)
		local pattern = "^(%d+)([mu]?s)$"
		local _, _, n, unit = string.find(str, pattern)
		if not (n and unit) then
			parser:error("failed to parse time '"..str.."', it should match '"..pattern.."' pattern")
		end
		return {n=tonumber(n), unit=unit}
	end

	parser:description("Redirects stream between devices, optionally mangling and delaying data.")
	parser:argument("srcDev", "Source device."):convert(tonumber)
	parser:argument("dstDev", "Destination device."):convert(tonumber)
	parser:option("-n", "Number of threads."):convert(tonumber):default(1)
	parser:option("-d --destination", "Rewrite destination IP.")
	parser:option("-m --ethDst", "Rewrite destination MAC."):convert(convertMac_fake)
	parser:option("--delay", "Delay in us."):convert(tonumber):default(0)
	parser:option("--buf", "Buffer size."):convert(tonumber)
	parser:flag("--debug", "Debug ring buffer.")
end

function master(args)
	local srcDev = device.config{port = args.srcDev, rxQueues = args.n}
	local dstDev = device.config{port = args.dstDev, txQueues = args.n}

	srcDev:wait()
	dstDev:wait()

	for i = 0, args.n - 1 do
		mg.startTask("task", srcDev:getRxQueue(i), dstDev:getTxQueue(i), args)
	end
	
	mg.waitForTasks()
end

local function gettimeofday_n()
	local sec, usec = gettimeofday()
	return tonumber(sec), tonumber(usec)
end

local zero16 = hton16(0)

function task(rxQ, txQ, args)
	if args.debug then
		log:setLevel("DEBUG")
	end

	local ipDst = args.destination and parseIPAddress(args.destination)
	local ethDst = args.ethDst and parseMacAddress(args.ethDst, true)
	
	local txStats = stats:newDevTxCounter(txQ, "plain")
	local rxStats = stats:newDevRxCounter(rxQ, "plain")

	local ringSize
	local ringBuffer = {}
	do
		local bufs0 = memory.bufArray(args.buf) -- NB: args.buf may be nil
		local buf_size = bufs0.size

		local delay = args.delay; if delay <= 0 then delay = 1 end
		local extra = 4.0 -- just in case
		local _, e = math.frexp(14.88 * delay * extra / buf_size)
		if e < 2 then e = 2 end
		ringSize = bit.lshift(1, e)
		log:debug("buf size: %d, ringSize: %d, e: %d", buf_size, ringSize, e)

		ringBuffer[0] = { bufs = bufs0 }
		for i = 1, ringSize-1 do
			ringBuffer[i] = { bufs = memory.bufArray(buf_size) }
		end
	end
	local ringDblSize = ringSize * 2

	-- ring buffer pointers (not using "tx", "rx" due to confusion), ax is to be "greater" than bx
	local ax = 0
	local bx = 0

	local function do_write()
		-- TODO: use bit operations
		while (ax - bx) % ringDblSize ~= 0 do
			local item = ringBuffer[bx % ringSize]
			local sec, usec = gettimeofday_n()
			local delta_usec = (sec - item.sec) * 1000000 + (usec - item.usec)

			if delta_usec > args.delay then
				log:debug("WRITE %03x, %03x, delta: %d", ax, bx, delta_usec)
				txQ:send(item.bufs)
				txStats:update()

				bx = (bx + 1) % ringDblSize
			else
				if delta_usec < 0 then
					log:warn("Oops, something wrong with time")
				end
				return
			end
		end
	end

	local function do_read()
		-- TODO: use bit operations
		if (ax - bx) % ringDblSize ~= ringSize then
			local item = ringBuffer[ax % ringSize]
			local bufs = item.bufs
			item.sec, item.usec = gettimeofday_n()
			local rx = recv_nb(rxQ, bufs)

			--bufs:freeAfter(rx)
			if rx == 0 then
				return
			end

			log:debug("READ %03x, %03x", ax, bx)
			ax = (ax + 1) % ringDblSize

			for i = 1, rx do
				local buf = bufs[i]
				local pkt = buf:getTcpPacket(ipv4)
				if ethDst then
					pkt.eth.dst:set(ethDst)
					pkt.eth.src:set(txQ.dev:getMac(true))
				end
				if ipDst then pkt.ip4.dst:set(ipDst) end
				--pkt.ip4:setChecksum(0)
				pkt.ip4.cs = zero16 -- FIXME: setChecksum() is extremely slow
			end
			bufs:resize(rx)
			bufs:offloadTcpChecksums(ipv4)
			
			rxStats:update()
		else
			log:warn("Buffer is full")
		end
	end
	
	while mg.running() do
		do_read()
		do_write()
	end

	rxStats:finalize()
	txStats:finalize()
end
