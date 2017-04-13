local mg		= require "moongen"
local memory		= require "memory"
local device		= require "device"
local ts		= require "timestamping"
local hist		= require "histogram"
local log		= require "log"
local timer		= require "timer"
local limiter		= require "software-ratecontrol"

local ETH_DST	= "11:12:13:14:15:16"


function master(txPort, rxPort, pattern, threads, pktSize, rate, waitTime)
	if not rxPort or not txPort or not threads or not pktSize or not rate then
		errorf("usage: txPort rxPort threads pktSize rate [waitTime]")
	end

	--if (((pktSize+26)*8) > (1000*ipt)) then
	--	errorf("requested packet size and inter-packet time is infeasible")
	--end

	local rxDev = device.config{ port = rxPort, rxDescs = 4096, dropEnable = true }
	local txDev = device.config{ port = txPort, txQueues = threads, disableOffloads = true, dropEnable = false }
	-- rxDev:wait()
	-- txDev:wait()
	device.waitForLinks()

	local queue = rxDev:getRxQueue(0)
	-- queue:enableTimestampsAllPackets()
	local total = 0
	local bufs = memory.createBufArray()
	local times = {}
	local sizes = {}
	local timer = timer:new(waitTime)

	for i = 1, threads do
		-- local pktRate = (1000.0 * rate) / pktSize
		mg.startTask("loadSlave", txDev:getTxQueue(i - 1), txDev, rate, i, threads, pktSize)
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
				print(sz, ts-last)
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
	for i, v in ipairs(sizes) do
		print(i,v)
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



function loadSlave(queue, txDev, rate, threadId, numThreads, pktSize)
	local ETH_DST	= "11:12:13:14:15:16"
	local PKT_SIZE  = 60

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
	local dist = pattern == "poisson" and poissonDelay or function(x) return x end
	while mg.running() do
		bufs:alloc(pktSize)
		for _, buf in ipairs(bufs) do
			buf:setDelay(dist(10^10 / numThreads / 8 / (rate * 10^6) - pktSize - 24))
		--	--buf:setDelay(1000000)
		end
		-- the rate here doesn't affect the result afaict.  It's just to help decide the size of the bad pkts
		queue:sendWithDelay(bufs, rate * numThreads)
		--queue:send(bufs)
	end
end




