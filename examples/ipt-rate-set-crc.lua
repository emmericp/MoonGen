local mg		= require "moongen"
local memory		= require "memory"
local device		= require "device"
local ts		= require "timestamping"
local hist		= require "histogram"
local log		= require "log"
local timer		= require "timer"
local limiter		= require "software-ratecontrol"
local stats     = require "stats"

local ETH_DST	= "11:12:13:14:15:16"


function master(txPort, rxPort, pattern, threads, pktSize, rate, waitTime)
	if not rxPort or not txPort or not threads or not pktSize or not rate then
		errorf("usage: txPort rxPort pattern threads pktSize rate [waitTime]")
		return
	end

	--if (((pktSize+26)*8) > (1000*ipt)) then
	--	errorf("requested packet size and inter-packet time is infeasible")
	--end

	--local rxDev = device.config{ port = rxPort, rxDescs = 4096, dropEnable = true }
	--local txDev = device.config{ port = txPort, txQueues = threads, disableOffloads = true, dropEnable = false }
	-- rxDev:wait()
	-- txDev:wait()
<<<<<<< HEAD
	--device.waitForLinks()
=======
	device.waitForLinks()
>>>>>>> d1110772cdaf2ee21f1845884b2565922ef3bb12
	
	local queue = rxDev:getRxQueue(0)
	queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray()
	local times = {}
	local sizes = {}
	local timer = timer:new(waitTime)
	
	local txDev = device.config({port = args.txDev, txQueues = 2, rxQueues = 2, disableOffloads = true})
	local rxDev = device.config({port = args.rxDev, txQueues = 2, rxQueues = 2})
	device.waitForLinks()
	
	mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(0), args.rate, PKT_SIZE)
	mg.startTask("timerSlave", txDev:getTxQueue(1), rxDev:getRxQueue(1), PKT_SIZE)
	mg.waitForTasks()
	
	for i = 1, threads do
		-- local pktRate = (1000.0 * rate) / pktSize
		mg.startTask("loadSlave", txDev:getTxQueue(i - 1), txDev, rate, i, threads, pktSize)
		mg.startTask("timerSlave", txDev:getTxQueue(i), rxDev:getRxQueue(i), PKT_SIZE)
	end

	local hsz = hist:create()
	local last = 0
	while mg.running() do
		local n = queue:recv(bufs)
		for i = 1, n do
			--if timer:expired() then
				local ts = bufs[i]:getTimestamp()
				times[#times + 1] = ts
				local sz = bufs[i].pkt_len
				-- print(i, sz, ts, ts-last)
				last = ts
				sizes[#sizes + 1] = sz
				hsz:update(sz)
			--end
		end
		total = total + n
		bufs:free(n)
	end

	mg.waitForTasks()

	hsz:print()
	hsz:save("sizes.csv")
	--for i, v in ipairs(sizes) do
	--	print(i,v)
	--end

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

function timerSlave(txQueue, rxQueue, size)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = histogram:new()
	-- wait for a second to give the other task a chance to start
	mg.sleepMillis(1000)
	local rateLimiter = timer:new(0.001)
	while mg.running() do
		rateLimiter:reset()
		hist:update(timestamper:measureLatency(size))
		rateLimiter:busyWait()
	end
	hist:print()
	hist:save("histogram.csv")
end



function loadSlave2(queue, txDev, rate, threadId, numThreads, pktSize)
	local ETH_DST	= "11:12:13:14:15:16"
	local PKT_SIZE  = 60

        local mem = memory.createMemPool(function(buf)
                buf:getEthernetPacket():fill{
                        ethSrc = txDev,
                        ethDst = ETH_DST,
                        ethType = 0x1234
                }
        end)
        local bufs = mem:bufArray()
        while mg.running() do
                bufs:alloc(PKT_SIZE)
                queue:send(bufs)
        end
end



function loadSlave333(queue, txDev, rate, threadId, numThreads, pktSize)
	local ETH_DST	= "11:12:13:14:15:16"
	--local PKT_SIZE  = 60
	
	-- doing crc rate control requires us to know the link speed.
	-- it is given in Mbps, just like the rate argument
	local linkspeed = txDev:getLinkStatus().speed
	print("linkspeed = "..linkspeed)
	
	local mem = memory.createMemPool{n=4096, func=function(buf)
	--local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethSrc = txDev,
			ethDst = ETH_DST,
			ethType = 0x1234
		}
	end}

	-- larger batch size is useful when sending it through a rate limiter
	local bufs = mem:bufArray()  --(128)
	-- local dist = pattern == "poisson" and poissonDelay or function(x) return x end
	while mg.running() do
		bufs:alloc(pktSize)
		for _, buf in ipairs(bufs) do
			--buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - pktSize - 24))
		--	--buf:setDelay(1000000)
			buf:setDelay((pktSize+24) * (linkspeed/rate - 1) )
		end
		-- the rate here doesn't affect the result afaict.  It's just to help decide the size of the bad pkts
		queue:sendWithDelay(bufs, rate * numThreads)
		--queue:send(bufs)
	end
end

function loadSlave(queue, dev, rate, threadId, numThreads, size)
	print("using packet size "..size)
	local linkspeed = dev:getLinkStatus().speed
	
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethType = 0x1234
		}
	end)
	local bufs = mem:bufArray()
	local txStats = stats:newManualTxCounter(dev, "plain")
	while mg.running() do
		bufs:alloc(size)
		for _, buf in ipairs(bufs) do
			buf:setDelay((size+24) * (linkspeed/rate - 1) )
		end
		txStats:updateWithSize(queue:sendWithDelay(bufs), size)
	end
	txStats:finalize()
end



