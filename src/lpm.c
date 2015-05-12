#include "lpm.h"
#include <rte_config.h>
#include <rte_table_lpm.h>
#include <rte_table.h>

/**
 * @file
 * MG lpm
 *
 * This is a simple wrapper around the rte_table_lpm algorithm.
 * It is needed, as the LUA JIT is not able to access the
 * rte_table_ops structure.
 *
 * Documentation for the respective functions can be found in rte_table.h
 ***/

void* mg_lpm_table_create(void *params, int socket_id, uint32_t entry_size)
{
  return rte_table_lpm_ops.f_create(params, socket_id, entry_size);
}

int mg_lpm_table_free(void *table){
  return rte_table_lpm_ops.f_free(table);
}

int mg_lpm_table_entry_add(
	void *table,
	void *key,
	void *entry,
	int *key_found,
	void **entry_ptr)
{
  return rte_table_lpm_ops.f_add(table, key, entry, key_found, entry_ptr);
}

int mg_lpm_table_entry_delete(
	void *table,
	void *key,
	int *key_found,
	void *entry)
{
  return rte_table_lpm_ops.f_delete(table, key, key_found, entry);
}

int mg_lpm_table_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries)
{
  return rte_table_lpm_ops.f_lookup(table, pkts, pkts_mask, lookup_hit_mask, entries);
}


