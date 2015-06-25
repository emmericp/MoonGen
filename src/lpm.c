#include "lpm.h"
#include <rte_config.h>
#include <rte_table_lpm.h>
#include <rte_table.h>
#include <rte_mbuf.h>

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
void printhex(void* data, int len){
  int i;
  for(i=0;i<len;i++){
    printf("%2x ", ((uint8_t*)data)[i]);
  }
  printf("\n");

}
void* mg_lpm_table_create(void *params, int socket_id, uint32_t entry_size)
{
  printf("params: ");
  printhex(params, 24);
  return rte_table_lpm_ops.f_create(params, socket_id, entry_size);
}

int mg_lpm_table_free(void *table){
  return rte_table_lpm_ops.f_free(table);
}

//void printhex(void* data, int len){
//  uint8_t *data8 = data;
//  while(len--){
//    printf("%2x ", data8++);
//  }
//}

int mg_lpm_table_entry_add_simple(
    void *table,
    uint32_t ip,
    uint8_t depth,
    void *entry){
  struct rte_table_lpm_key key;
  key.ip = ip;
  key.depth = depth;
  printf("add key: ");
  printhex(&key, 5);
  printf("add entry: ");
  printhex(entry, 11);
  int key_found;
  void *entry_ptr;
  return rte_table_lpm_ops.f_add(table, &key, entry, &key_found, &entry_ptr);
}

int mg_lpm_table_entry_add(
	void *table,
	void *key,
	void *entry,
	int *key_found,
	void **entry_ptr)
{
  printf("add key: ");
  printhex(key, 5);
  printf("add entry: ");
  printhex(entry, 5);
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
	//uint64_t *lookup_hit_mask,
  struct mg_lpm4_routes * routes)
{
  struct rte_pktmbuf pkt0 = pkts[0]->pkt;
  printf("headroom: %d\n", rte_pktmbuf_headroom(pkts[0]));
  //void * data = pkt0.data+128;
  void * data = pkt0.data;
  int i;
  printf("data = \n");
  for(i=0;i<256;i++){
    printf("%2x ", ((uint8_t*)data)[i]);
  }
  printf("\n");

  // FIXME: XXX: pkts_mask hardcoded to 1 for debugging
  int result = rte_table_lpm_ops.f_lookup(table, pkts, 1, &routes->hit_mask, &(routes->entries));
  printf("hit mask c : ");
  printhex(&routes->hit_mask, 8);
  printf("C result entry[0]: ");
  printhex(&routes->entries[0], 5);

  return result;
}


