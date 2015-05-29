#ifndef __INCLUDE_MG_DISTRIBUTE_H__
#define __INCLUDE_MG_DISTRIBUTE_H__

#include <stdint.h>
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include "bitmask.h"



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

#endif
