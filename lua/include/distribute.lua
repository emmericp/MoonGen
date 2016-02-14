---------------------------------
--- @file distribute.lua
--- @brief Distribute ...
--- @todo TODO docu
---------------------------------

local ffi = require "ffi"
local dpdk = require "dpdk"
local serpent = require "Serpent"
local log = require "log"

ffi.cdef [[
struct mg_distribute_queue{
  uint16_t next_idx;
  uint16_t size;
  struct rte_mbuf *pkts[0];
};

struct mg_distribute_output{
  uint8_t valid;
  uint8_t port_id;
  uint16_t queue_id;
  uint64_t timeout;
  uint64_t time_first_added;
  struct mg_distribute_queue *queue;
};

struct mg_distribute_config{
  uint16_t entry_offset;
  uint16_t nr_outputs;
  uint8_t always_flush;
  struct mg_distribute_output outputs[0];
};


inline int8_t mg_distribute_enqueue(
  struct mg_distribute_queue * queue,
  struct rte_mbuf *pkt
  ){
  queue->pkts[queue->next_idx] = pkt;
  queue->next_idx++;
  // TODO: is switch here faster?
  // Attention: Order is relevant here, as a queue with size 1
  // should always trigger a flush and never timestamping
  if(unlikely(queue->next_idx == queue->size)){
    return 2;
  }
  if(unlikely(queue->next_idx == 1)){
    return 1;
  }
  return 0;
}

struct mg_distribute_config * mg_distribute_create(
    uint16_t entry_offset,
    uint16_t nr_outputs,
    uint8_t always_flush
    );

int mg_distribute_output_flush(
  struct mg_distribute_config *cfg,
  uint16_t number
  );

int mg_distribute_register_output(
  struct mg_distribute_config *cfg,
  uint16_t number,
  uint8_t port_id,
  uint16_t queue_id,
  uint16_t burst_size,
  uint64_t timeout
  );

int mg_distribute_send(
  struct mg_distribute_config *cfg,
  struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
  void **entries
  );

void mg_distribute_handle_timeouts(
  struct mg_distribute_config *cfg
  );
]]


local mod = {}

local mg_distribute = {}
mod.mg_distribute = mg_distribute
mg_distribute.__index = mg_distribute


function mod.createDistributor(socket, entryOffset, nrOutputs, alwaysFlush)
  socket = socket or select(2, dpdk.getCore())
  entryOffset = entryOffset or 0
  if alwaysFlush then
    alwaysFlush = 1
  else
    alwaysFlush = 0
  end

  return setmetatable({
    cfg = ffi.gc(ffi.C.mg_distribute_create(entryOffset, nrOutputs, alwaysFlush), function(self)
      log:debug("lpm garbage")
      ffi.C.mg_NOT_YET_IMPLEMENTED(self) -- FIXME
    end),
    socket = socket
  }, mg_distribute)
end


function mg_distribute:__serialize()
	return "require 'distribute'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('distribute').mg_distribute"), true
end

function mg_distribute:send(packets, bitMask, routingEntries)
  return ffi.C.mg_distribute_send(self.cfg, packets.array, bitMask.bitmask, ffi.cast("void **", routingEntries.array))
end

function mg_distribute:registerOutput(outputNumber, txQueue, bufferSize, timeout)
  -- FIXME: is this a good idea, to use uint64_t bit integers in lua??
  local f_cpu = dpdk.getCyclesFrequency()
  local cycles_timeout = tonumber(f_cpu * timeout)

  local portID = txQueue.id
  local queueID = txQueue.qid

  log:info("register output NR " .. tostring(outputNumber) .. " -> port = " .. tostring(portID) .. " queue = " .. tostring(queueID) .. " timeout = " .. tostring(cycles_timeout))
  ffi.C.mg_distribute_register_output(self.cfg, outputNumber, portID, queueID, bufferSize, cycles_timeout)
end

function mg_distribute:handleTimeouts()
  ffi.C.mg_distribute_handle_timeouts(self.cfg)
  return
end

return mod
