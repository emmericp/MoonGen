local mg = require "moongen"

require "number-assert"

describe("l3-multi-destinations", function()
	it("should run with IPv4", function()
		local proc = mg.start("./examples/l3-multi-destinations.lua", 10, "10.0.0.1", 10, 100)
		finally(function() proc:destroy() end)
		proc:waitForPorts(1)
		--[[
				output should look like this:
				[Output] INFO: Detected an IPv4 address.
				[Output] Start sending...
				[Output] 18:44:28.100845 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x0800 (IP4)
				[Output] IP4 192.168.1.1 > 10.0.0.1 ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 (UDP) cksum 0x0000
				[Output] UDP 1024 > 1025 len 28 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 0800 4500 
				[Output]   0x0010:   0030 0000 0000 4011 0000 c0a8 0101 0a00 
				[Output]   0x0020:   0001 0400 0401 001c 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 0000 0000 0000 0000 0000 
				[Output] 
				[Output] 18:44:28.100929 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x0800 (IP4)
				[Output] IP4 192.168.1.1 > 10.0.0.2 ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 (UDP) cksum 0x0000
				[Output] UDP 1024 > 1025 len 28 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 0800 4500 
				[Output]   0x0010:   0030 0000 0000 4011 0000 c0a8 0101 0a00 
				[Output]   0x0020:   0002 0400 0401 001c 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 0000 0000 0000 0000 0000 
				[Output] 
				[Output] 18:44:28.100969 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x0800 (IP4)
				[Output] IP4 192.168.1.1 > 10.0.0.3 ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 (UDP) cksum 0x0000
				[Output] UDP 1024 > 1025 len 28 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 0800 4500 
				[Output]   0x0010:   0030 0000 0000 4011 0000 c0a8 0101 0a00 
				[Output]   0x0020:   0003 0400 0401 001c 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 0000 0000 0000 0000 0000 
				[Output] 
				[Output] 0.10024 19072
				[Output] 0.10002 18944
				[Output] 0.10002 18944
				[Output] 0.10002 18944
		]]--
		
		local type = proc:waitFor("INFO: Detected an IPv(%d) address.")
		assert.are.same(4, tonumber(type))

		local str = proc:waitFor("IP4 192.168.1.1 > (%S+) ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 %(UDP%) cksum 0x0000")
		assert.are.same("10.0.0.1", str)
		
		str = proc:waitFor("IP4 192.168.1.1 > (%S+) ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 %(UDP%) cksum 0x0000")
		assert.are.same("10.0.0.2", str)
		
		str = proc:waitFor("IP4 192.168.1.1 > (%S+) ver 4 ihl 5 tos 0 len 48 id 0 flags 0 frag 0 ttl 64 proto 0x11 %(UDP%) cksum 0x0000")
		assert.are.same("10.0.0.3", str)
	
		-- ignore first measurement
		proc:waitFor("0%.(%S+) (%S+)")
		proc:waitFor("0%.(%S+) (%S+)")

		local ts1, rate1 = proc:waitFor("(%S+) (%S+)")
		local ts2, rate2 = proc:waitFor("(%S+) (%S+)")
		ts1, ts2 = tonumber(ts1), tonumber(ts2)
		rate1, rate2 = tonumber(rate1), tonumber(rate2)
		assert.rel_range(ts1, 0.1, 5)
		assert.rel_range(rate1, 19000, 5)
		assert.rel_range(ts2, 0.1, 5)
		assert.rel_range(rate2, 19000, 5)

		proc:kill()
	end)
	
	it("should run with IPv6", function()
		local proc = mg.start("./examples/l3-multi-destinations.lua", 10, "fe80::1234", 10, 100)
		finally(function() proc:destroy() end)
		proc:waitForPorts(1)
		--[[
				output should look like this:
				[Output] INFO: Detected an IPv6 address.
				[Output] Start sending...
				[Output] 19:32:4.416726 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x86dd (IP6)
				[Output] IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > fe80:0000:0000:0000:0000:0000:0000:1234 ver 6 tc 0 fl 0 len 8 next 0x11 (UDP) ttl 64
				[Output] UDP 1024 > 1025 len 8 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 86dd 6000 
				[Output]   0x0010:   0000 0008 1140 fd06 0000 0000 0000 0000 
				[Output]   0x0020:   0000 0000 0001 fe80 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 1234 0400 0401 0008 0000 
				[Output] 
				[Output] 19:32:4.416834 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x86dd (IP6)
				[Output] IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > fe80:0000:0000:0000:0000:0000:0000:1235 ver 6 tc 0 fl 0 len 8 next 0x11 (UDP) ttl 64
				[Output] UDP 1024 > 1025 len 8 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 86dd 6000 
				[Output]   0x0010:   0000 0008 1140 fd06 0000 0000 0000 0000 
				[Output]   0x0020:   0000 0000 0001 fe80 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 1235 0400 0401 0008 0000 
				[Output] 
				[Output] 19:32:4.416885 ETH 90:e2:ba:2c:cb:02 > 90:e2:ba:35:b5:81 type 0x86dd (IP6)
				[Output] IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > fe80:0000:0000:0000:0000:0000:0000:1236 ver 6 tc 0 fl 0 len 8 next 0x11 (UDP) ttl 64
				[Output] UDP 1024 > 1025 len 8 cksum 0x0000
				[Output]   0x0000:   90e2 ba35 b581 90e2 ba2c cb02 86dd 6000 
				[Output]   0x0010:   0000 0008 1140 fd06 0000 0000 0000 0000 
				[Output]   0x0020:   0000 0000 0001 fe80 0000 0000 0000 0000 
				[Output]   0x0030:   0000 0000 1236 0400 0401 0008 0000 
				[Output] 
				[Output] 0.10011 19072
				[Output] 0.10002 18944
				[Output] 0.10002 18944
				[Output] 0.10002 18944
		]]--
		
		local type = proc:waitFor("INFO: Detected an IPv(%d) address.")
		assert.are.same(6, tonumber(type))
		
		local str = proc:waitFor("IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > (%S+) ver 6 tc 0 fl 0 len 8 next 0x11 %(UDP%) ttl 64")
		assert.are.same("fe80:0000:0000:0000:0000:0000:0000:1234", str)
		
		local str = proc:waitFor("IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > (%S+) ver 6 tc 0 fl 0 len 8 next 0x11 %(UDP%) ttl 64")
		assert.are.same("fe80:0000:0000:0000:0000:0000:0000:1235", str)
		
		local str = proc:waitFor("IP6 fd06:0000:0000:0000:0000:0000:0000:0001 > (%S+) ver 6 tc 0 fl 0 len 8 next 0x11 %(UDP%) ttl 64")
		assert.are.same("fe80:0000:0000:0000:0000:0000:0000:1236", str)
		
		-- ignore first measurement
		proc:waitFor("0%.(%S+) (%S+)")
		proc:waitFor("0%.(%S+) (%S+)")

		local ts1, rate1 = proc:waitFor("(%S+) (%S+)")
		local ts2, rate2 = proc:waitFor("(%S+) (%S+)")
		ts1, ts2 = tonumber(ts1), tonumber(ts2)
		rate1, rate2 = tonumber(rate1), tonumber(rate2)
		assert.rel_range(ts1, 0.1, 5)
		assert.rel_range(rate1, 19000, 5)
		assert.rel_range(ts2, 0.1, 5)
		assert.rel_range(rate2, 19000, 5)

		proc:kill()
	end)

end)


