local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local lpm     = require "lpm"
local serpent = require "Serpent"
local ffi     = require "ffi"
local bitmask = require "bitmask"
local filters = require "filter"
local lshift = bit.lshift
local distribute = require "distribute"
local arp = require "proto.arp"
local ip = require "proto.ip4"

ffi.cdef [[
struct table_entry {
  uint32_t ip_next_hop;
  uint8_t interface;
  struct mac_address mac_next_hop;
};
]]

function master(txPort, ...)
  -- configure the device (setup queues + RSS)
  local txDev = device.config({port=txPort, rxQueues=4+4, txQueues=4, rssNQueues=4})
  device.waitForLinks()

  -- XXX this is the actual queue ID starting with 0 as the first queue
  -- TODO: update this in moongen documentation
  local arpRxQueue = txDev:getRxQueue(5)
  local arpTxQueue = txDev:getTxQueue(3)
  dpdk.launchLuaOnCore(2, arp.arpTask, {rxQueue = arpRxQueue, txQueue = arpTxQueue, ips = {"10.0.0.130", "10.0.0.10", "10.0.0.11", "10.0.0.12", "10.0.0.13", "10.0.0.129"}})
  print("ARP slave running")

  -- Create a new routing table.
  -- The Table entry is given as our user specified C datatype:
  local lpmTable = lpm.createLpm4Table(nil, nil, "struct table_entry")

  -- We add some entries to our routing table:
  local entry = lpmTable:allocateEntry()
  entry.ip_next_hop = parseIPAddress("10.0.0.0")
  entry.interface = 0
  entry.mac_next_hop = parseMacAddress("ab:00:00:ba:12:34")

  lpmTable:addEntry(parseIPAddress("10.0.0.0"), 25, entry)

  -- We can reuse the same entry...
  entry.ip_next_hop = parseIPAddress("10.0.0.1")
  entry.interface = 1
  entry.mac_next_hop = parseMacAddress("ab:00:00:ba:12:35")

  lpmTable:addEntry(parseIPAddress("10.0.0.128"), 25, entry)

  entry.ip_next_hop = parseIPAddress("10.0.0.1")
  entry.interface = 2
  entry.mac_next_hop = parseMacAddress("ab:00:00:ba:12:36")

  -- more specific route to 10.0.0.130
  lpmTable:addEntry(parseIPAddress("10.0.0.130"), 32, entry)


  -- we create a distributor, which will distribute packets to output
  -- queues according to the result of the routing algorithm
  -- (This is basically an output redirection table)
  local distributor = distribute.createDistributor(nil, 4, 4, false)
  -- register outputs
  distributor:registerOutput(0, txDev:getTxQueue(0), 64, 1)
  distributor:registerOutput(1, txDev:getTxQueue(1), 64, 5)
  distributor:registerOutput(2, txDev:getTxQueue(2), 64, 2)

  -- create a 5tuple filter, which matches packets with destination ipv4
  -- addr of 10.0.0.10
  txDev:addHW5tupleFilter({dst_ip = parseIPAddress("10.0.0.10"), l4protocol = 0}, txDev:getRxQueue(4))

  -- Run the actual routing core:
  dpdk.launchLua("slave", lpmTable, distributor, {txDev:getRxQueue(0), txDev:getRxQueue(1), txDev:getRxQueue(2), txDev:getRxQueue(3), txDev:getRxQueue(4)}, 128)
  dpdk.waitForSlaves()
  collectgarbage("collect")
end

--function slave(lpmTable_table, txDev, rxDev)
function slave(lpmTable, distributor, rxQueues, maxBurstSize)
  --print("slave here")

  -- Allocate mbufs for packets...:
  local mem = memory.createMemPool()
  local bufs = mem:bufArray(maxBurstSize)

  -- Create a bitmask (specifies, for which packets we want to do the lookup):
  local in_mask = bitmask.createBitMask(maxBurstSize)

  -- Create an other Bitmask, to see for which packets a route could be found:
  local out_mask = bitmask.createBitMask(maxBurstSize)

  -- Allocate Entry pointers, which will point to the routing table entries
  -- for all routed packets:
  local entries = lpmTable:allocateEntryPtrs(maxBurstSize)

  local nrx

  while dpdk.running() do
    local nrxmax = 0
    -- RR Arbiter over all configured rxQueues:
    for i, rxQueue in ipairs(rxQueues) do
      -- try to receive a maximum of maxBurstSize of packets/mbufs:
      nrx = rxQueue:tryRecv(bufs, 0)
      if (nrx > 0) then
        print("rxed on queue " .. tostring(rxQueue.qid))
        -- prepare in_mask for the received packets
        in_mask:clearAll()
        in_mask:setN(nrx)
        -- FIXME: do we need to clear out_mask too ?

        -- Decrement TTL, and detect packets with TTL <=1
        lpm.decrementTTL(bufs, in_mask, in_mask)
        -- TODO: the right place would be in memory.lua
        --  but masks might confuse
        
        -- ---
        -- Branch to slow path for ICMP will come here...
        -- ---

        -- Do the lookup for the whole burst:
        lpmTable:lookupBurst(bufs, in_mask, out_mask, entries)

        -- Apply the routes
        -- (write destination mac address to packets)
        lpm.applyRoute(bufs, out_mask, entries, 5)

        -- IP checksum should be calculated in hardware
        bufs:offloadIPChecksums(nil, nil, nil, nrx)

        -- Send packets to their designated interfaces
        -- (distributor also writes correct src mac addr to packets)
        distributor:send(bufs, out_mask, entries)

        -- nrxmax is used to estimate the workload of this core
        if (nrx > nrxmax) then
          nrxmax = nrx
        end
      end
    end
    
    -- handle timeouts
    -- This is an implementation of daniel's idea of only flushing, when we have nothing to do.
    -- We assume, if we only received small bursts, the router has not much to do
    -- Under full load, flows, with little traffic will starve :(
    if(nrxmax < maxBurstSize/2) then
      distributor:handleTimeouts()
    end
  end

  -- this is just for testing garbage collection
  collectgarbage("collect")
end
