#include <rte_config.h>
#include <rte_common.h>
#include <rte_ring.h>
#include "ring.h"

// DPDK SPSC bounded ring buffer

struct rte_ring* create_ring(uint32_t count, int32_t socket) {
	static volatile uint32_t ring_cnt = 0;
	char ring_name[32];
	sprintf(ring_name, "mbuf_ring%d", __sync_fetch_and_add(&ring_cnt, 1));
	return rte_ring_create(ring_name, count, socket, RING_F_SP_ENQ | RING_F_SC_DEQ);
}

int ring_enqueue(struct rte_ring* r, void* const* obj, int n) {
	return rte_ring_sp_enqueue_bulk(r, obj, n);
}

int ring_dequeue(struct rte_ring* r, void** obj, int n) {
	return rte_ring_sc_dequeue_bulk(r, obj, n);
}

