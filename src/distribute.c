#include "distribute.h"

#include <rte_cycles.h>
#include <rte_ethdev.h>
#include "rte_malloc.h"

struct mg_distribute_config * mg_distribute_create(
  uint16_t entry_offset,
  uint16_t nr_outputs,
  uint8_t always_flush
  ){
  struct mg_distribute_config *cfg = rte_zmalloc(NULL, sizeof(struct mg_distribute_config) + nr_outputs * sizeof(struct mg_distribute_output), 0);
  if(cfg){
    cfg->nr_outputs = nr_outputs;
    cfg->always_flush = always_flush;
    cfg->entry_offset = entry_offset;
  }
  return cfg;
}

int mg_distribute_output_flush(
  struct mg_distribute_config *cfg,
  uint16_t number
  ){
  struct mg_distribute_queue * queue = cfg->outputs[number].queue;
  if(queue->next_idx == 0){
    printf(" output %d should have been flushed, but was empty!\n", number);
    return 0;
  }
  // Busy wait, until all packets are stored in tx descriptors.
  // TODO: maybe use a ring for the queue datastructure and do not do bust wait here
  while(queue->next_idx>0){
    uint16_t transmitted = rte_eth_tx_burst (cfg->outputs[number].port_id, cfg->outputs[number].queue_id, queue->pkts, queue->next_idx);
    queue->next_idx -= transmitted;
  }
  printf(" output %d has been flushed!\n", number);
  return 0;
}


// ATTENTION: Queue size must be at least one!!
int mg_distribute_register_output(
  struct mg_distribute_config *cfg,
  uint16_t number,
  uint8_t port_id,
  uint16_t queue_id,
  uint16_t burst_size,
  uint64_t timeout
  ){
  if(number >= cfg->nr_outputs){
    printf("ERROR: invalid outputnumber\n");
    return -EINVAL;
  }
  cfg->outputs[number].port_id = port_id; 
  cfg->outputs[number].queue_id = queue_id; 
  cfg->outputs[number].timeout = timeout; 
  cfg->outputs[number].valid = 1; 
  if(burst_size != 0){
    // allocate a queue for the output
    // Aligned to cacheline...
    // FIXME: MACRO for cacheline size?
    struct mg_distribute_queue *queue = rte_zmalloc(NULL, sizeof(struct mg_distribute_queue) + burst_size * sizeof(struct rte_mbuf*), 64);
    cfg->outputs[number].queue = queue;
    cfg->outputs[number].queue->size = burst_size; 
  }
  return 0;
}

int mg_distribute_send(
  struct mg_distribute_config *cfg,
  struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
  void **entries
  ){
  
  // TODO: performance considerations:
  //  - loop unrolling (is compiler doing that?)
  //  - we always iterate multiple of 64...
  //    -> maybe save cycles, when burst is not multiple of 64?
  int i;
  for(i = 0; i < pkts_mask->n_blocks; i++){
    uint64_t mask = 1ULL;
    while(mask){
      mask = mask<<1;
      if(mask & pkts_mask->mask[i]){
        // determine output, to send the packet to
        uint8_t output = ((uint8_t*)(*entries))[cfg->entry_offset];
        // send pkt to the corresponding output...
        int8_t status = mg_distribute_enqueue(cfg->outputs[output].queue, *pkts);
        if( unlikely( status  == 2  ) ){
          // packet was enqueued, but queue is full
          // flush queue
          mg_distribute_output_flush(cfg, output);
        }
        if( unlikely( status  == 1  ) ){
          // packet was enqueued, queue was empty
          // record the time, for possible future timeout
          cfg->outputs[output].time_first_added = rte_rdtsc();
        }
      }
      pkts++;
      entries++;
    }
  }

  if(unlikely(cfg->always_flush)){
    int i;
    //FIXME check if output valid
    for (i = 0; i < cfg->nr_outputs; i++){
      if(likely(cfg->outputs[i].valid)){
        mg_distribute_output_flush(cfg, i);
      }
    }
  }
  return 0;
}


// I was thinking hard about using the dpdk provided timer modules.
// I decided to implement my own system here because
// - dpdk uses one shared timer list for all cores
//  -> we do not want shared timers and the resulting locking overhead
// - dpdk only supports callback functions
//  -> we do not want to have a callback function for every queue...
//  -> it is hard to pass userdata (which queue to flush) to this function
// - we still can use dpdk timers to call this handle_timeout function
//  in fixed intervals, to reduce load/latency in the case the dpdk timer is used
//  somewhere in the future

// Call frequency of this function defines the resolution of timeouts for
// queue flushes.
void mg_distribute_handle_timeouts(
  struct mg_distribute_config *cfg
  ){
  int i;
  uint64_t time = rte_rdtsc();
  struct mg_distribute_output *output = cfg->outputs;
  for (i = 0; i < cfg->nr_outputs; i++){
    if(likely(output->valid)){
      if(output->time_first_added + output->timeout < time){
        // timeout hit -> flush queue
        printf("timeout of output %d was hit\n", i);
        mg_distribute_output_flush(cfg, i);
      }
    }
    output++;
  }
}
