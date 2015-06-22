#ifndef MG_LPM_H
#define MG_LPM_H
#include <stdint.h>

#include <rte_config.h>
#include <rte_mbuf.h>

struct mg_lpm4_table_entry {
  uint32_t ip_next_hop;
  uint8_t interface;
  uint8_t mac_address[6];
};

struct mg_lpm4_routes {
  struct mg_lpm4_table_entry entries[64];
  uint64_t hit_mask;
};

void* mg_lpm_table_create(void *params, int socket_id, uint32_t entry_size);

int mg_lpm_table_free(void *table);

int mg_lpm_table_entry_add(
	void *table,
	void *key,
	void *entry,
	int *key_found,
	void **entry_ptr);

int mg_lpm_table_entry_add_simple(
    void *table,
    uint32_t ip,
    uint8_t depth,
    void *entry);

int mg_lpm_table_entry_delete(
	void *table,
	void *key,
	int *key_found,
	void *entry);

int mg_lpm_table_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	//uint64_t *lookup_hit_mask,
  struct mg_lpm4_routes * routes);
//int mg_lpm_table_lookup(
//	void *table,
//	struct rte_mbuf **pkts,
//	uint64_t pkts_mask,
//	uint64_t *lookup_hit_mask,
//	void **entries);
#endif
