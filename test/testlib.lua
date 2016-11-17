-- Testlib.lua Library

-- Provides a set of master functions for the test framework.
-- Requires a valid config.lua to work.
-- Requires luaunit to deliver correct test results.
-- Some slaves need to return a boolean value for correct test results.
-- masterPairX-functions effectively execute each slave twice with switched input devices.

-- Available functions:
--	- testlib.setRuntime()
--		-- Set the runtime for all slaves called
--	- testlib.masterSingle()
--		-- Starts one slave for each card
--		-- (Called functions: slave(dev,card))
--	- testlib.masterPairSingle()
--		-- Starts one slave for each pairing
--		-- (Called functions: slave(rxDev, txDev, rxCard, txCard))
--	- testlib.masterPairMulti()
--		-- Starts two slaves for each pairing and a compare function to compare their returned values
--		-- (Called functions: slave1(rxDev, txDev), slave2(rxDev, txDev), compare(slave1return, slave2return))

local testlib = {}

local dpdk	= require "dpdk"
local tconfig	= require "tconfig"
local timer	= require "timer"
local device	= require "device"
local luaunit	= require "luaunit"
local log	= require "testlog"

-- Init runtime
testlib.wait = 10

-- Init test array
Tests = {}

-- Get runtime for all slaves
function testlib:getRuntime()
	return testlib.wait
end

-- Set the runtime for all slaves | default 10 seconds
function testlib:setRuntime( value )
	testlib.wait = value
	log:info("Runtime per test set to " .. testlib:getRuntime() .. " seconds.")
end

-- Start one slave on every available device
function testlib:masterSingle()
	-- Init devices
	local cards = tconfig.cards()
	local devs = {}
	for i=1 , #cards do
		devs[ i ] = device.config{ port = cards[ i ][ 1 ] , rxQueues = 2 , txQueues = 2 }
	end
	device.waitForLinks()
	
	-- Iterates over all devices to:
	--	- Start a slave with the device as input
	for i = 1 , #cards do
		Tests[ "Tested device: " .. cards[ i ][ 1 ] ] = function()
			log:info( "Testing device: " .. cards[ i ][ 1 ] )
			local result = slave( devs[ i ] , cards[ i ] )
			dpdk.waitForSlaves()
			luaunit.assertTrue( result )
		end
	end
	
	-- Run luaunit
	os.exit( luaunit.LuaUnit.run() )

end

-- Start two slaves for every pairing
function testlib:masterPairSingle()
	
	-- Init devices
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()
	local devs = {}
	local devInf = {}
	for i = 1 , #pairs  do
		devs[ i ]	= device.config{ port = cards[ pairs[ i ][ 1 ] + 1 ][ 1 ] , rxQueues = 2 , txQueues = 2 }
		devInf[ i ]	= cards[ pairs[ i ][ 1 ] + 1 ]
		devs[ i + 1 ]	= device.config{ port = cards[ pairs[ i ][ 2 ] + 1 ][ 1 ] , rxQueue = 2 , txQueue = 2 }
		devInf[ i + 1 ]	= cards[ pairs[ i ][ 2 ] + 1 ]
	end
	device.waitForLinks()
	
	-- Iterates over all device pairings to:
	--	- Start a set of slaves for the pairing
	for i=1 , #devs , 2 do
		Tests[ "Tested device: " .. i ] = function()
			log:info( "Testing device: " .. cards[ pairs[ i ][ 1 ] + 1 ][ 1 ] .. " (" .. cards[ pairs[ i ][ 2 ] + 1 ][ 1 ] .. ")" )
			local result = slave( devs[ i ] , devs[ i + 1 ] , devInf[ i ] , devInf[ i + 1 ] )
			luaunit.assertTrue( result )
		end
		-- Mirror input devices
		Tests[ "Tested device: " .. i + 1 ] = function()
			log:info( "Testing device: " .. cards[ pairs[ i ][ 2 ] + 1 ][ 1 ] .. " (" .. cards[ pairs [ i ][ 1 ] + 1 ][ 1 ] .. ")" )
			local result = slave( devs[ i + 1 ] , devs[ i ] , devInf[ i + 1 ] , devInf[ i ] )
			luaunit.assertTrue( result )
		end
	end
	
	-- Run luaunit
	os.exit( luaunit.LuaUnit.run() )
	
end

-- Start two pairs of slaves for every available decive pairing
function testlib:masterPairMulti()
	-- Init devices
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()
	local devs = {}
	for i = 1 , #pairs  do
		if not devs[ pairs[ i ][ 1 ] ] then
			devs[ pairs[ i ][ 1 ] ]	= device.config{ port = pairs[ i ][ 1 ] , rxQueues = 2 , txQueues = 2 }
		end
		if not devs[ pairs[ i ][ 2 ] ] then
			devs[ pairs[ i ][ 2 ] ] = device.config{ port = pairs[ i ][ 2 ] , rxQueue = 2 , txQueue = 2 }
		end
	end
	device.waitForLinks()
	
	-- Iterates over all pairings to:
	--	- Start two sets of slaves for the pairing
	-- - Call a compare function to compare their output
	for i = 1 , #pairs do
		local dev1 = pairs[ i ][ 1 ]
		local dev2 = pairs[ i ][ 2 ]
		Tests[ "Tested device: " .. i ] = function()
			log:info( "Testing device: " .. pairs[ i ][ 1 ] .. " (" .. pairs[ i ][ 2 ] .. ")")
			local slave1 = dpdk.launchLua( "slave1" , devs[ dev1 ] , devs[ dev2 ] )
			local slave2 = dpdk.launchLua( "slave2" , devs[ dev1 ] , devs[ dev2 ] , result1 )
			local return1 = slave1:wait()
			local return2 = slave2:wait()
			local returnC = compare( return1 , return2 )
			luaunit.assertTrue( returnC )
		end
		-- Mirror input devices
		Tests[ "Tested device: " .. i .. "(2)" ] = function ()
			log:info( "Testing device: " .. pairs[ i ][ 2 ].. " (" .. pairs[ i ][ 1 ] .. ")" )
			local slave1 = dpdk.launchLua( "slave1" , devs[ dev2 ] , devs[ dev1 ] )
			local slave2 = dpdk.launchLua( "slave2" , devs[ dev2 ] , devs[ dev1 ] )
			local return1 = slave1:wait()
			local return2 = slave2:wait()
			local returnC = compare( return1 , return2 )
			luaunit.assertTrue( returnC )
		end
	end
	
	-- Run luaunit
	os.exit( luaunit.LuaUnit.run() )

end

-- Return library
return testlib
