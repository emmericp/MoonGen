local mg		= require "moongen"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local log 		= require "log"
local ip4		= require "proto.ip4"
local libmoon	= require "libmoon"
local dpdkc		= require "dpdkc"
local ffi		= require "ffi"
local syscall	= require "syscall"

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
	parser:option("--buf", "Buffer size."):convert(tonumber):default(63)
	parser:flag("--debug", "Debug ring buffer.")
end

function master(args)
	local shm_filename = "/MoonGen"
	local shm_fd, err = syscall.shm_open(shm_filename, "CREAT,RDWR,EXCL", "RUSR,WUSR")
	if not shm_fd then
		error("shm_open(%s, ...) failed: %s", shm_filename, err)
	end

	local srcDev = device.config{port = args.srcDev, rxQueues = args.n}
	local dstDev = device.config{port = args.dstDev, txQueues = args.n}

	srcDev:wait()
	dstDev:wait()

	for i = 0, args.n - 1 do
		mg.startTask("task", shm_filename, srcDev:getRxQueue(i), dstDev:getTxQueue(i), args)
	end
	
	mg.waitForTasks()
	syscall.close(shm_fd)
	syscall.shm_unlink(shm_filename)
end

local function gettimeofday_n()
	local sec, usec = gettimeofday()
	return tonumber(sec), tonumber(usec)
end

local zero16 = hton16(0)

function task(shm_filename, rxQ, txQ, args)
	local ethSrc = txQ.dev:getMac(true)
	local packetLen = 60
	local chunkSize = args.buf + 1
	
	local mem = memory.createMemPool()

	local ipDst = args.destination and parseIPAddress(args.destination)
	local ethDst = args.ethDst and parseMacAddress(args.ethDst, true)
	
	local txStats = stats:newDevTxCounter(txQ, "plain")
	local rxStats = stats:newDevRxCounter(rxQ, "plain")

	local ringSize
	do
		local delay = args.delay; if delay <= 0 then delay = 1 end
		local extra = 2.0 -- just in case
		local _, e = math.frexp(14.88 * delay * extra / args.buf)
		if e < 2 then e = 2 end
		ringSize = bit.lshift(1, e)
		log:info("buf size: %d, ringSize: %d, e: %d", args.buf, ringSize, e)
	end
	local ringDblSize = ringSize * 2

	local ringBufferRaw, ax_ptr, bx_ptr
	local cleanupFunc
	do
		local shm_fd, err = syscall.shm_open(shm_filename, "RDWR", "RUSR,WUSR")
		if not shm_fd then
			error("shm_open(%s, ...) failed: %s", shm_filename, err)
		end
		local memSize = ringSize * chunkSize * packetLen
		local ptr, err = syscall.mmap(nil, memSize+8, "READ,WRITE", "SHARED,ANONYMOUS", shm_fd, 0)
		if not ptr then
			error("nmap(...) failed: %s", err)
		end
		ringBufferRaw = ffi.cast("uint8_t*", ptr)
		ax_ptr = ffi.cast("volatile uint32_t*", ringBufferRaw+memSize)
		bx_ptr = ffi.cast("volatile uint32_t*", ringBufferRaw+memSize+4)

		cleanupFunc = function() syscall.munmap(ptr, memSize+8); syscall.close(shm_fd) end
	end
	
	if args.debug then
		log:setLevel("DEBUG")
	end

	local mem = memory.createMemPool()
	local bufs_write = mem:bufArray(chunkSize - 1)
	local bufs_read = mem:bufArray(chunkSize - 1)

	-- ring buffer pointers (not using "tx", "rx" due to confusion), ax is to be "greater" than bx
	local ax, bx = 0, 0
	ax_ptr[0] = 0
	bx_ptr[0] = 0

	local function do_write()
		ax = ax_ptr[0]
		bx = bx_ptr[0]
		-- TODO: use bit operations
		while (ax - bx) % ringDblSize ~= 0 do
			local chunkIdx = bx % ringSize

			local meta_raw = ffi.cast("uint32_t*", ringBufferRaw + (((chunkIdx + 1) * chunkSize - 1) * packetLen))
			log:debug("WRITE phase 0: %d %d %d", meta_raw[0], meta_raw[1], meta_raw[2])
			local sec, usec = gettimeofday_n()
			local delta_usec = (sec - meta_raw[1]) * 1000000 + (usec - meta_raw[2])

			if delta_usec > args.delay then
				log:debug("WRITE %03x, %03x, delta: %d", ax, bx, delta_usec)
				
				bufs_write:resize(meta_raw[0])
				bufs_write:alloc(packetLen)
			
				for i, buf in ipairs(bufs_write) do
					local pkt = buf:getTcpPacket(ipv4)
					if pkt.ip4:getProtocol() == ip4.PROTO_TCP then
						if ethDst then
							pkt.eth.dst:set(ethDst)
							pkt.eth.src:set(ethSrc)
						end
						if ipDst then pkt.ip4.dst:set(ipDst) end
						--pkt.ip4:setChecksum(0)
						pkt.ip4.cs = zero16 -- FIXME: setChecksum() is extremely slow
					end

					local pkt_raw = ringBufferRaw + ((chunkIdx * chunkSize + i-1) * packetLen)
					local pktSize = ffi.cast("uint32_t*", pkt_raw)[0]
					buf:setSize(pktSize)
					ffi.copy(buf:getData(), pkt_raw+4, pktSize)
				end
				bufs_write:offloadTcpChecksums(ipv4)
				txQ:send(bufs_write)

				txStats:update()

				bx = (bx + 1) % ringDblSize
				bx_ptr[0] = bx
			else
				if delta_usec < 0 then
					log:warn("Oops, something wrong with time")
				end
				return
			end
		end
	end

	local function do_read()
		ax = ax_ptr[0]
		bx = bx_ptr[0]
		-- TODO: use bit operations
		if (ax - bx) % ringDblSize ~= ringSize then
			local chunkIdx = ax % ringSize

			local sec, usec = gettimeofday_n()
			local rx = recv_nb(rxQ, bufs_read)

			bufs_read:freeAfter(rx)
			if rx == 0 then
				return
			end

			log:debug("READ %03x, %03x", ax, bx)
			ax = (ax + 1) % ringDblSize
			ax_ptr[0] = ax

			for i = 1, rx do
				local buf = bufs_read[i]

				local pkt_raw = ringBufferRaw + ((chunkIdx * chunkSize + i-1) * packetLen)
				ffi.cast("uint32_t*", pkt_raw)[0] = buf:getSize()
				ffi.copy(pkt_raw + 4, buf:getRawPacket(), buf:getSize())
			end

			local meta_raw = ffi.cast("uint32_t*", ringBufferRaw + (((chunkIdx + 1) * chunkSize - 1) * packetLen))
			meta_raw[0], meta_raw[1], meta_raw[2] = rx, sec, usec

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
	cleanupFunc()
end
