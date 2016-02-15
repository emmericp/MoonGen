-- Testlib.lua Library

-- Provides a set of master functions for the test framework.
-- Requires a valid config.lua to work.
-- Requires luaunit to deliver correct test results.
-- Some slaves need to return a boolean value for correct test results.

-- Available functions:
--	- testlib.setRuntime()
--		-- Set the runtime for all slaves called
--	- testlib.masterSingle()
--		-- Starts a slave for all available cards
--		-- (Called functions: slave(dev,card))
--	- testlib.masterPairSingle()
--		-- Start two slave for each available card pairing
--		-- (Called functions: slave(rxDev, txDev, rxCard, txCard))
--	- testlib.masterPairMulti()
--		-- Start two pairs of slaves for each available card pairing
--		-- (Called functions: slave1(rxDev, txDev), slave2(txDev, rxDev, slave1return))

local testlib = {}

local dpdk	= require "dpdk"
local tconfig	= require "tconfig"
local timer	= require "timer"
local device	= require "device"
local luaunit	= require "luaunit"
local log	= require "testlog"

testlib.wait = 10

Tests = {}

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
	
	local cards = tconfig.cards()
	local devs = {}
	
	for i=1 , #cards do
		devs[ i ] = device.config{ port = cards[ i ][ 1 ] , rxQueues = 2 , txQueues = 2 }
	end
	device.waitForLinks()
	dpdk.sleepMillis( 100 )

	local runtime = timer:new( testlib:getRuntime() )
	log:info("Current runtime set to " .. testlib:getRuntime() .. " seconds.")
	
	-- Iterates over all devices to do the following:
	--	- Start a slave with the device as input
	--	- Check the output of the slave if it equals true
	for i = 1 , #cards do
		
		Tests[ "Tested device: " .. cards[ i ][ 1 ] ] = function()

			log:info( "Testing device: " .. cards[ i ][ 1 ] )
			local result = slave( devs[ i ] , cards[ i ] )
			dpdk.waitForSlaves()
			luaunit.assertTrue( result )

		end
		
	end
	
	os.exit( luaunit.LuaUnit.run() )

end

-- Start two slaves for every pairing
function testlib:masterPairSingle()
	
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
	dpdk.sleepMillis( 100 )
	
	for i=1 , #devs , 2 do
		
		Tests[ "Tested device: " .. i ] = function()
		
			log:info( "Testing device: " .. cards[ pairs[ i ][ 1 ] + 1 ][ 1 ] .. " (" .. cards[ pairs[ i ][ 2 ] + 1 ][ 1 ] .. ")" )

			local result = slave( devs[ i ] , devs[ i + 1 ] , devInf[ i ] , devInf[ i + 1 ] )

			luaunit.assertTrue( result )
		end
		
		Tests[ "Tested device: " .. i + 1 ] = function()

			log:info( "Testing device: " .. cards[ pairs[ i ][ 2 ] + 1 ][ 1 ] .. " (" .. cards[ pairs [ i ][ 1 ] + 1 ][ 1 ] .. ")" )

			local result = slave( devs[ i + 1 ] , devs[ i ] , devInf[ i + 1 ] , devInf[ i ] )

			luaunit.assertTrue( result )
			
		end
		
	end
	
	os.exit( luaunit.LuaUnit.run() )
	
end

-- Start two pairs of slaves for every available decive pairing
function testlib:masterPairMulti()
	
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
	
	-- Iterates over all pairings to do the following:
	--	- Start two pairs of slaves for every device pairing
	--	- Every pair consists of the same pair of slaves
	--	- The devices are switched in the second call
	--	- The first slave receives both devices and returns a value, that will be passed to the second slave
	-- - The second slave receives both devices and the return value of the first slave
	--	- Checks the output of the second slave if it equals true
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
		
		Tests[ "Tested device: " .. i + 1 ] = function ()
			log:info( "Testing device: " .. pairs[ i ][ 2 ].. " (" .. pairs[ i ][ 1 ] .. ")" )
			
			local slave1 = dpdk.launchLua( "slave1" , devs[ dev2 ] , devs[ dev1 ] )
			local slave2 = dpdk.launchLua( "slave2" , devs[ dev2 ] , devs[ dev1 ] )
			
			local return1 = slave1:wait()
			local return2 = slave2:wait()
			local returnC = compare( return1 , return2 )
			luaunit.assertTrue( returnC )
		end
	end
	
	os.exit( luaunit.LuaUnit.run() )

end

return testlib
