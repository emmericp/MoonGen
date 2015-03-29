local dpdk		= require "dpdk"
local pipe		= require "pipe"
local timer		= require "timer"

function master()
	local p = pipe:newSlowPipe()
	p:send(1, 2, 3, 4)
	p:send("string")
	p:send({ foo = "bar", 1, 2, 3, subtable = {1}})
	dpdk.launchLua("slave", p)
	dpdk.sleepMillis(50)
	p:send("delayed")
	dpdk.waitForSlaves()

	p = pipe:newSlowPipe()
	dpdk.launchLua("numProducer", p)
	dpdk.launchLua("consumer", p)
	dpdk.waitForSlaves()

	p = pipe:newSlowPipe()
	dpdk.launchLua("stringProducer", p)
	dpdk.launchLua("consumer", p)
	dpdk.waitForSlaves()

	p = pipe:newSlowPipe()
	dpdk.launchLua("tblProducer", p)
	dpdk.launchLua("consumer", p)
	dpdk.waitForSlaves()
end


function slave(pipe)
	local a, b, c, d = pipe:recv()
	assert(a == 1 and b == 2 and c == 3 and d == 4)
	assert(pipe:recv() == "string")
	local obj = pipe:recv()
	assert(obj.foo == "bar")
	assert(obj[2] == 2)
	assert(obj.subtable[1] == 1)
	assert(pipe:tryRecv(10 * 1000) == nil)
	dpdk.sleepMillis(40)
	assert(pipe:tryRecv(1000) == "delayed")
end


function numProducer(pipe)
	local timer = timer:new(10)
	local i = 0
	while timer:running() do
		i = i + 1
		pipe:send(i)
	end
	printf("Sent %d number objects, %f kmessages per second", i, i / 10 / 10^3)
end

function stringProducer(pipe)
	local timer = timer:new(10)
	local i = 0
	while timer:running() do
		i = i + 1
		pipe:send("stringtest" .. tostring(i))
	end
	printf("Sent %d string objects, %f kmessages per second", i, i / 10 / 10^3)
end

function tblProducer(pipe)
	local timer = timer:new(10)
	local i = 0
	while timer:running() do
		i = i + 1
		pipe:send({ foo = i })
	end
	printf("Sent %d tbl objects, %f kmessages per second", i, i / 10 / 10^3)
end

function consumer(pipe)
	local timer = timer:new(10)
	local i = 0
	while timer:running() do
		local obj = pipe:tryRecv(1000)
		if obj then
			i = i + 1
		end
	end
	printf("Received %d objects, %f kmessages per second", i, i / 10 / 10^3)
end

