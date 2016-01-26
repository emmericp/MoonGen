EXPORT_ASSERT_TO_GLOBALS = true

local luaunit	= require "luaunit"
local dpdk	= require "dpdk" -- TODO: rename dpdk module to "moongen"
local memory	= require "memory"
local device	= require "device"
local timer	= require "timer"

local testlib	= require "testlib"
local tconfig	= require "tconfig"

local PKT_SIZE  = 124 -- without CRC

function master()
	testlib.masterSingle()
end

function slave(dev, rate)
	local queue = dev:getTxQueue(0)
	dpdk.sleepMillis(100)
 
	local mem = memory.createMemPool(function(buf)
			buf:getEthernetPacket():fill{
				pktLength = PKT_SIZE,
				ethSrc = "10:11:12:13:14:15", --random src
				ethDst = "10:11:12:13:14:15", --random dst
			}
		end)
	
	local bufs = mem:bufArray()
	local runtime = timer:new(1)
	local i = 0
	while runtime:running() and dpdk.running() do
		bufs:alloc(PKT_SIZE)
		queue:send(bufs)
		i = i + 1
	end

	return rate < i/13
end
