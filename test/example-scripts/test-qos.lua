local mg = require "moongen"

require "number-assert"

describe("quality-of-service-test example", function()
	it("should run", function()
		local proc = mg.start("./examples/quality-of-service-test.lua", 8, 9, 100, 1000)
		finally(function() proc:destroy() end)
		proc:waitForPorts(2)
		--[[
				output should look like this:
				[Output] [RxQueue: id=9, qid=0] Port 42: Received 18 packets, current rate 0.00 Mpps, 0.00 MBit/s, 0.00 MBit/s wire rate
				[Output] [TxQueue: id=8, qid=0] Sent 976500 packets, current rate 0.98 Mpps, 999.91 MBit/s, 1156.15 MBit/s wire rate
				[Output] [RxQueue: id=9, qid=0] Port 43: Received 97610 packets, current rate 0.10 Mpps, 99.95 MBit/s, 115.57 MBit/s wire rate
				[Output] [RxQueue: id=9, qid=0] Port 42: Received 976617 packets, current rate 0.98 Mpps, 1000.04 MBit/s, 1156.29 MBit/s wire rate
				[Output] [TxQueue: id=8, qid=1] Sent 97902 packets, current rate 0.10 Mpps, 100.22 MBit/s, 115.87 MBit/s wire rate
				[Output] [TxQueue: id=8, qid=0] Sent 1953063 packets, current rate 0.98 Mpps, 999.95 MBit/s, 1156.20 MBit/s wire rate
				[Output] [RxQueue: id=9, qid=0] Port 43: Received 195263 packets, current rate 0.10 Mpps, 100.00 MBit/s, 115.62 MBit/s wire rate
				[Output] [RxQueue: id=9, qid=0] Port 42: Received 1953130 packets, current rate 0.98 Mpps, 999.95 MBit/s, 1156.19 MBit/s wire rate
				[Output] [TxQueue: id=8, qid=1] Sent 195552 packets, current rate 0.10 Mpps, 99.98 MBit/s, 115.60 MBit/s wire rate
		]]--
		
		-- ignore first measurement
		proc:waitFor("Sent %d+ packets, current rate (%S+) Mpps")
		proc:waitFor("Sent %d+ packets, current rate (%S+) Mpps")

		local rate1 = proc:waitFor("qid=0.* Sent %d+ packets, current rate (%S+) Mpps")
		local rate2 = proc:waitFor("qid=1.* Sent %d+ packets, current rate (%S+) Mpps")
		rate1, rate2 = tonumber(rate1), tonumber(rate2)
		assert.rel_range(rate1, 1, 5)
		assert.rel_range(rate2, 0.1, 5)

		-- should also be receiving at that rate
		rate1 = proc:waitFor("Port 42: Received %d+ packets, current rate (%S+) Mpps")
		rate2 = proc:waitFor("Port 43: Received %d+ packets, current rate (%S+) Mpps")
		rate1, rate2 = tonumber(rate1), tonumber(rate2)
		assert.rel_range(rate1, 1, 5)
		assert.rel_range(rate2, 0.1, 5)
		proc:kill()
	end)

end)


