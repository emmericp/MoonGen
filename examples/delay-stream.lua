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

local shm_filename = "/MoonGen"
local packetLen = 60
local packetSpace = packetLen + 4

local function setup(isMaster, taskNum, args)
	if args.debug then
		log:setLevel("DEBUG")
	end

	local shm_filename = shm_filename .. "-" .. tostring(taskNum)

	local chunkSize = args.buf + 1
	local delay = args.delay; if delay <= 0 then delay = 1 end
	local extra = 10.0 -- just in case
	local _, e = math.frexp(14.88 * delay * extra / args.buf)
	if e < 2 then e = 2 end
	local ringSize = bit.lshift(1, e)
	if isMaster then log:info("buf size: %d, ringSize: %d, e: %d", args.buf, ringSize, e) end
	local ringDblSize = ringSize * 2

	local oflags
	if isMaster then oflags = "CREAT,RDWR,EXCL" else oflags = "RDWR" end

	local shm_fd, err = syscall.shm_open(shm_filename, oflags, "RUSR,WUSR")
	if not shm_fd then
		if err.EXIST then
			-- try to unlink and retry to open
			syscall.shm_unlink(shm_filename)
			shm_fd, err = syscall.shm_open(shm_filename, oflags, "RUSR,WUSR")
		end
		if not shm_fd then
			errorf("shm_open(\"%s\", ...) failed: %s", shm_filename, err)
		end
	end
	local ringRawSize = ringSize * chunkSize * packetSpace
	local shm_size = ringRawSize + 8
	local ok, err = syscall.ftruncate(shm_fd, shm_size)
	if not ok then
		errorf("ftruncate(...) failed: %s", err)
	end
	local ptr, err = syscall.mmap(nil, shm_size, "READ,WRITE", "SHARED", shm_fd, 0)
	if not ptr then
		errorf("nmap(...) failed: %s", err)
	end
	local ringBufferRaw = ffi.cast("uint8_t*", ptr)
	local ax_ptr = ffi.cast("volatile uint32_t*", ringBufferRaw+ringRawSize)
	local bx_ptr = ffi.cast("volatile uint32_t*", ringBufferRaw+ringRawSize+4)

	local cleanupFunc
	if isMaster then
		ax_ptr[0] = 0
		bx_ptr[0] = 0
		cleanupFunc = function()
			syscall.munmap(ptr, shm_size)
			syscall.close(shm_fd)
			syscall.shm_unlink(shm_filename)
		end
	else
		cleanupFunc = function() syscall.munmap(ptr, shm_size); syscall.close(shm_fd) end
	end

	return cleanupFunc, ringSize, chunkSize, ringBufferRaw, ax_ptr, bx_ptr
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
	local cleanupFuncs = {}
	for i = 1, args.n do
		cleanupFuncs[i] = setup(true, i, args)
	end

	local srcDev, dstDev
	if args.srcDev == args.dstDev then
		srcDev = device.config{port = args.srcDev, rxQueues = args.n, txQueues = args.n}
		dstDev = srcDev
	else
		srcDev = device.config{port = args.srcDev, rxQueues = args.n}
		dstDev = device.config{port = args.dstDev, txQueues = args.n}
	end
	srcDev:wait()
	dstDev:wait()

	for i = 0, args.n - 1 do
		mg.startTask("task_read", i+1, srcDev:getRxQueue(i), args)
		mg.startTask("task_write", i+1, dstDev:getTxQueue(i), args)
	end
	
	mg.waitForTasks()
	for _, f in ipairs(cleanupFuncs) do f() end
end

local function gettimeofday_n()
	local sec, usec = gettimeofday()
	return tonumber(sec), tonumber(usec)
end

local zero16 = hton16(0)

function task_read(taskNum, rxQ, args)
	local cleanupFunc, ringSize, chunkSize, ringBufferRaw, ax_ptr, bx_ptr = setup(false, taskNum, args)
	local ringDblSize = ringSize * 2

	local rxStats = stats:newDevRxCounter(rxQ, "plain")
	local totStats = stats:newPktRxCounter("total:" .. tostring(taskNum))
	local ringStats = stats:newPktRxCounter("ring:" .. tostring(taskNum))
	local manStats = stats:newManualRxCounter("man:" .. tostring(taskNum))
	local timesBufferFull = 0

	local mem = memory.createMemPool()
	local bufs_read = mem:bufArray(chunkSize - 1)

	-- ring buffer pointers (not using "tx", "rx" due to confusion), ax is to be "greater" than bx
	local ax, bx = 0, 0

	local c = 0
	local xxxMac = parseMacAddress("90:e2:ba:d0:dd:e0", true)
	while mg.running() do
		bx = bx_ptr[0]
		-- TODO: use bit operations
		if (ax - bx) % ringDblSize ~= ringSize then
			local sec, usec = gettimeofday_n()
			local rx = rxQ:recv(bufs_read)
			bufs_read:freeAfter(rx)
			manStats:update(rx, 0)

			local chunkIdx = ax % ringSize
			for i = 1, rx do
				local buf = bufs_read[i]
				local pkt = buf:getTcpPacket(ipv4)
				local bufSize = buf:getSize()

				local pkt_raw = ringBufferRaw + ((chunkIdx * chunkSize + i-1) * packetSpace)
				if bufSize <= 60 and pkt.eth.dst:get() == xxxMac
				then
					ringStats:countPacket(buf)
					ffi.cast("uint32_t*", pkt_raw)[0] = bufSize
					ffi.copy(pkt_raw + 4, buf:getRawPacket(), bufSize)
				else
					ffi.cast("uint32_t*", pkt_raw)[0] = 0
					if c < 3 then
						buf:dump()
						c = c + 1
					end
				end
				totStats:countPacket(buf)
			end

			local meta_raw = ffi.cast("volatile uint32_t*", ringBufferRaw + (((chunkIdx + 1) * chunkSize - 1) * packetSpace))
			meta_raw[0], meta_raw[1], meta_raw[2] = rx, sec, usec
			log:debug("READ-%d %03x, %03x", taskNum, ax, bx)
			ax = (ax + 1) % ringDblSize
			ax_ptr[0] = ax

			rxStats:update()
			totStats:update()
			ringStats:update()
		else
			if timesBufferFull == 0 then
				log:warn("Buffer is full")
			end
			timesBufferFull = timesBufferFull + 1
		end
	end

	rxStats:finalize()
	totStats:finalize()
	ringStats:finalize()
	manStats:finalize()
	if timesBufferFull ~= 0 then
		log:warn("Buffer was full %d times", timesBufferFull)
	end
	cleanupFunc()
end

function task_write(taskNum, txQ, args)
	local cleanupFunc, ringSize, chunkSize, ringBufferRaw, ax_ptr, bx_ptr = setup(false, taskNum, args)
	local ringDblSize = ringSize * 2

	local ipDst = args.destination and parseIPAddress(args.destination)
	local ethDst = args.ethDst and parseMacAddress(args.ethDst, true)
	local ethSrc = txQ.dev:getMac(true)
	
	local txStats = stats:newDevTxCounter(txQ, "plain")

	local mem = memory.createMemPool()
	local bufs_write = mem:bufArray(chunkSize - 1)

	-- ring buffer pointers (not using "tx", "rx" due to confusion), ax is to be "greater" than bx
	local ax, bx = 0, 0

	local function do_write()
		ax = ax_ptr[0]
		-- TODO: use bit operations
		while (ax - bx) % ringDblSize ~= 0 do
			local chunkIdx = bx % ringSize
			local meta_raw = ffi.cast("volatile uint32_t*", ringBufferRaw + (((chunkIdx + 1) * chunkSize - 1) * packetSpace))
			local sec, usec = gettimeofday_n()
			local delta_usec = (sec - meta_raw[1]) * 1000000 + (usec - meta_raw[2])

			if delta_usec > args.delay then
				log:debug("WRITE-%d %03x, %03x, delta: %d", taskNum, ax, bx, delta_usec)

				local nRecvd = meta_raw[0]
				if nRecvd > chunkSize - 1 then
					nRecvd = chunkSize - 1
					log:warn("Probably garbage in ring buffer (nRecvd): %d > %d", nRecvd, chunkSize-1)
				end
				bufs_write:resize(nRecvd)
				bufs_write:alloc(packetLen)

				local i = 0
				for j = 0, nRecvd-1 do
					local pkt_raw = ringBufferRaw + ((chunkIdx * chunkSize + j) * packetSpace)
					local pktSize = ffi.cast("uint32_t*", pkt_raw)[0]
					if pktSize ~= 0 then
						i = i + 1
						local buf = bufs_write[i]
						buf:setSize(pktSize)
						ffi.copy(buf:getData(), pkt_raw+4, pktSize)

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
					end
				end
				if i ~= 0 then
					bufs_write:resize(i)
					bufs_write:offloadTcpChecksums(ipv4)
					txQ:send(bufs_write)
				end
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

	while mg.running() do
		do_write()
	end

	txStats:finalize()
	cleanupFunc()
end
