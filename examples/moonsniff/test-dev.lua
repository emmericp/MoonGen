--- Forward packets between two ports
local lm     = require "libmoon"
local device = require "device"
local stats  = require "stats"
local log    = require "log"
local memory = require "memory"

function configure(parser)
	parser:argument("dev", "Devices to use, specify the same device twice to echo packets."):args(2):convert(tonumber)
	parser:option("-t --threads", "Number of threads per forwarding direction using RSS."):args(1):convert(tonumber):default(1)
	return parser:parse()
end

function master(args)
	-- configure devices
	for i, dev in ipairs(args.dev) do
		args.dev[i] = device.config{
			port = dev,
			txQueues = args.threads,
			rxQueues = args.threads,
			rssQueues = args.threads
		}
	end
	device.waitForLinks()

	-- print stats
	stats.startStatsTask{devices = args.dev}

	-- start forwarding tasks
	for i = 1, args.threads do
		lm.startTask("forward", args.dev[1]:getRxQueue(i - 1), args.dev[2]:getTxQueue(i - 1))
		-- bidirectional fowarding only if two different devices where passed
		if args.dev[1] ~= args.dev[2] then
			lm.startTask("forward", args.dev[2]:getRxQueue(i - 1), args.dev[1]:getTxQueue(i - 1))
		end
	end
	lm.waitForTasks()
end

function forward(rxQueue, txQueue)
	-- a bufArray is just a list of buffers that we will use for batched forwarding
	local bufs = memory.bufArray()
	while lm.running() do -- check if Ctrl+c was pressed
		-- receive one or more packets from the queue
		local count = rxQueue:recv(bufs)
		-- send out all received bufs on the other queue
		-- the bufs are free'd implicitly by this function
		txQueue:sendN(bufs, count)
	end
end

