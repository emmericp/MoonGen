#include <rte_config.h>
#include <rte_mempool.h>
#include <rte_mbuf.h>
#include <rte_errno.h>
#include <rte_spinlock.h>

#include <stdint.h>

#define MEMPOOL_CACHE_SIZE 256

#define MBUF_SIZE 2048


struct rte_mempool* init_mem(uint32_t nb_mbuf, int32_t socket) {
	static volatile uint32_t mbuf_cnt = 0;
	char pool_name[32];
	sprintf(pool_name, "mbuf_pool%d", __sync_fetch_and_add(&mbuf_cnt, 1));
	// rte_mempool_create is apparently not thread-safe :(
	static rte_spinlock_t lock = RTE_SPINLOCK_INITIALIZER;
	rte_spinlock_lock(&lock);
	struct rte_mempool* pool = rte_mempool_create(pool_name, nb_mbuf, MBUF_SIZE, MEMPOOL_CACHE_SIZE,
		sizeof(struct rte_pktmbuf_pool_private),
		rte_pktmbuf_pool_init, NULL,
		rte_pktmbuf_init, NULL,
		socket < 0 ? rte_socket_id() : (uint32_t) socket, 0
	);
	rte_spinlock_unlock(&lock);
	if (!pool) {
		printf("Memory allocation failed: %s (%d)\n", rte_strerror(rte_errno), rte_errno); 
		return 0;
	}
	return pool;
}

struct rte_mbuf* alloc_mbuf(struct rte_mempool* mp) {
	struct rte_mbuf* res = rte_pktmbuf_alloc(mp);
	return res;
}


uint16_t rte_mbuf_refcnt_read_export(struct rte_mbuf* m) {
	return rte_mbuf_refcnt_read(m);
}

uint16_t rte_mbuf_refcnt_update_export(struct rte_mbuf* m, int16_t value) {
	return rte_mbuf_refcnt_update(m, value);
}

