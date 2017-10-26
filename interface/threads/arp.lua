local mg      = require "moongen"
local arp     = require "proto.arp"

local thread = { arpDevices = {}, flows = {} }

local function doesArp(flow)
	for _,dep in pairs(flow.packet.depvars) do
		if dep.tbl[1] == "arp" then
			return true
		end
	end

	return false
end

local function addIp(dev, ip)
	-- luacheck: read globals ipString
	ip = ipString(ip) -- see dependencies/arp.lua

	local tbl = thread.arpDevices[dev]
	if not tbl then
		tbl = {}
		thread.arpDevices[dev] = tbl
	end

	tbl[ip] = true
end

function thread.prepare(flows, devices)
	for _,flow in ipairs(flows) do
		if doesArp(flow) then
			table.insert(thread.flows, flow)
			local ft = flow.packet.fillTbl

			for _,dev in ipairs(flow:property "tx") do
				addIp(dev, ft.ip4Src or ft.ip6Src)
			end

			for _,dev in ipairs(flow:property "rx") do
				addIp(dev, ft.ip4Dst or ft.ip6Dst)
			end
		end
	end

	for dev in pairs(thread.arpDevices) do
		devices:reserveTx(dev)
		devices:reserveRx(dev)
	end
end

function thread.start(devices)
	if #thread.flows == 0 then return end

	local queues = {}

	for dev, ips in pairs(thread.arpDevices) do
		local ipList = {}
		for ip in pairs(ips) do
			table.insert(ipList, ip)
		end

		table.insert(queues, {
			rxQueue = devices:rxQueue(dev),
			txQueue = devices:txQueue(dev),
			ips = ipList
		})
	end

	arp.startArpTask(queues)
	mg.startSharedTask("__INTERFACE_ARP_MANAGER", thread.flows)
end

local function arpManagerThread(flows)
	local isActive = true
	while isActive do
		mg.sleepMillis(1000)

		isActive = false
		for _,flow in ipairs(flows) do
			if not flow.properties.counter:isZero() then
				isActive = true
			end
		end
	end

	arp.stopArpTask()
end

__INTERFACE_ARP_MANAGER = arpManagerThread -- luacheck: globals __INTERFACE_ARP_MANAGER

return thread
