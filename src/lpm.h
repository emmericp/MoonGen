#ifndef MG_LPM_H
#define MG_LPM_H
#include <stdint.h>

#include <rte_config.h>
#include <rte_mbuf.h>
void* mg_lpm_table_create(void *params, int socket_id, uint32_t entry_size);

int mg_lpm_table_free(void *table);

int mg_lpm_table_entry_add(
	void *table,
	void *key,
	void *entry,
	int *key_found,
	void **entry_ptr);

int mg_lpm_table_entry_delete(
	void *table,
	void *key,
	int *key_found,
	void *entry);

int mg_lpm_table_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries);
#endif
