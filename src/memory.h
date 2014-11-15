#ifndef MEMORY_H__
#define MEMORY_H__

#include <rte_config.h>
#include <rte_mempool.h>
#include <rte_mbuf.h>

struct rte_mempool* init_mem(uint32_t nb_mbuf, int32_t socket);

#endif /* MEMORY_H__ */
