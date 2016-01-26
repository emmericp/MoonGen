local tconfig = require "tconfig"

local testlib = {}

function testlib.masterSingle()
	local cards = tconfig.cards()
	local devs = {}
	for i=1, #cards  do
		devs[i] = device.config{ port = cards[i][1], rxQueues = 2, txQueues = 2 }
	end
	device.waitForLinks()

	local Tests = {}
	for i = 1, #cards do
		Tests["testFunction" .. cards[i][1]] = function()
			luaunit.assertTrue( slave( devs[i], cards[i][3] ) )
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

function testlib.masterMulti()
	local cards = tconfig.cards()
	local pairs = tconfig.pairs()

	local devs = {}
	for i=1, #pairs, 2 do
		devs[i] = device.config{ port = cards[pairs[i][1]+1][1], rxQueues = 2, txQueues = 2 }
		devs[i+1] = device.config{ port = cards[pairs[i][2]+1][1], rxQueue = 2, txQueue = 2 }
	end
	device.waitForLinks()
    
	local Tests = {}
	local result = 0
	for i=1, #devs,2 do
		Tests["testFunction" .. i] = function()
			result = slave1( devs[i+1]:getTxQueue( 0 ) )
			luaunit.assertTrue( slave2( devs[i]:getRxQueue( 0 ), result ) )
		end
		Tests["testFunction" .. i+1] = function ()
			result = slave1( devs[i]:getTxQueue( 0 ) )
			luaunit.assertTrue( slave2( devs[i+1]:getRxQueue(0), result ) )
		end
	end
	os.exit( luaunit.LuaUnit.run() )
end

return testlib