local dpdk	= require "dpdk"
local memory	= require "memory"
local ts	= require "timestamping"
local device	= require "device"
local filter	= require "filter"
local timer	= require "timer"
local stats	= require "stats"
local hist	= require "histogram"
local log	= require "log"

local tconfig	= require "tconfig"
local testlib	= require "testlib"

local FLOWS = 4
local RATE = 2000
local PKT_SIZE = 124

function master()
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()

	local devs = {}
	for i=1, #pairs, 2 do
		devs[i] = device.config{ port = cards[pairs[i][1]+1][1], rxQueues = 2, txQueues = 2 }
		devs[i+1] = device.config{ port = cards[pairs[i][2]+1][1], rxQueues = 2, txQueues = 2 }
	end
	device.waitForLinks()

	local result = 0
	if(RATE > 0) then
		for i=i, #devs do
			devs[i]:getTxQueue(0):setRate(RATE - (PKT_SIZE + 4) * 8 / 1000)
		end
	end

	for i=1, #devs, 2 do
		Tests["Testing device: " .. i] = function()
			log:info("Testing device: " .. cards[pairs[i][1]+1][1])
			local slave1 = dpdk.launchLua( "slave1",  devs[i+1], devs[i] )
			local slave2 = dpdk.launchLua( "slave2", devs[i], devs[i+1] )
			local wait = timer:new(10)
			timer:wait()
			
			local return1 = slave1:wait()
			local return2 = slave2:wait()
			
			luaunit.assertEquals(return1, return2)
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

--loadSlave
function slave1(txDev, rxDev)
	local counter = 0

	local mempool = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			pktLength = PKT_SIZE,
			ethSrc = txQueue,
			ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
		}
	end)

	local bufs = mempool:bufArray()

	local queue = txDev:getTxQueue( 0 )

	local counter = 0
	local txCtr = stats:newDevTxCounter(queue, "plain")
	local rxCtr = stats:newDevRxCounter(rxDev, "plain")

	while dpdk.running() do
		bufs:alloc(PKT_SIZE)
		for i, buf in ipairs(bufs) do
			local pkt = buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = txQueue,
				ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
			}
			counter = incAndWrap(counter, FLOWS)
		end
	
		queue:send(bufs)
		txCtr:update()
		rxCtr:update()
	end
	txCtr:finalize()
	rxCtr:finalize()
	
	return counter
end

--timerSlave
function slave2(txDev, rxDev)
	local rxQueue = rxDev:getRxQueue(0)
	rxQueue.dev:filterTimestamps(rxQueue)
	local timestamper = ts:newTimestamper(txDev:getTxQueue(0), rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(1000)
	local counter = 0
	local rateLimit = timer:new(0.001)
	while dpdk.running() do
		hist:update(timestamper:measureLatency(PKT_SIZE, function(buf)
			local pkt = buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = txDev:getTxQueue(0),
				ethDst = "FF:FF:FF:FF:FF:FF:FF:FF"
			}
			counter = incAndWrap(counter, FLOWS)
		end))
		rateLimit:wait()
		rateLimit:reset()
	end
	dpdk.sleepMillis(300)
	hist:print()
	
	return counter
end
