/*-
 *   BSD LICENSE
 *
 *   Copyright(c) 2010-2014 Intel Corporation. All rights reserved.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <string.h>
#include <stdio.h>

#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_malloc.h>
#include <rte_byteorder.h>
#include <rte_log.h>
#include <rte_lpm.h>
#include <rte_memcpy.h>
#include <rte_ether.h>

#include "lpm_l.h"
#include "bitmask.h"
#include "debug.h"

#define RTE_TABLE_LPM_MAX_NEXT_HOPS                        256

struct rte_table_lpm {
	/* Input parameters */
	uint32_t entry_size;
	uint32_t entry_unique_size;
	uint32_t n_rules;
	uint32_t offset;

	/* Handle to low-level LPM table */
	struct rte_lpm *lpm;

	/* Next Hop Table (NHT) */
	uint32_t nht_users[RTE_TABLE_LPM_MAX_NEXT_HOPS];
	uint8_t nht[0] __rte_cache_aligned;
};

void *
mg_table_lpm_create(void *params, int socket_id, uint32_t entry_size)
{
	struct rte_table_lpm_params *p = (struct rte_table_lpm_params *) params;
	struct rte_table_lpm *lpm;
	uint32_t total_size, nht_size;

	/* Check input parameters */
	if (p == NULL) {
		RTE_LOG(ERR, TABLE, "%s: NULL input parameters\n", __func__);
		return NULL;
	}
	if (p->n_rules == 0) {
		RTE_LOG(ERR, TABLE, "%s: Invalid n_rules\n", __func__);
		return NULL;
	}
	if (p->entry_unique_size == 0) {
		RTE_LOG(ERR, TABLE, "%s: Invalid entry_unique_size\n",
			__func__);
		return NULL;
	}
	if (p->entry_unique_size > entry_size) {
		RTE_LOG(ERR, TABLE, "%s: Invalid entry_unique_size\n",
			__func__);
		return NULL;
	}
  // XXX ASK: does a 32 bit aligned offset make any sense here?
  //      this prevents me from accessing ip address in payload
	//if ((p->offset & 0x3) != 0) {
	//	RTE_LOG(ERR, TABLE, "%s: Invalid offset\n", __func__);
	//	return NULL;
	//}

	entry_size = RTE_ALIGN(entry_size, sizeof(uint64_t));

	/* Memory allocation */
	nht_size = RTE_TABLE_LPM_MAX_NEXT_HOPS * entry_size;
	total_size = sizeof(struct rte_table_lpm) + nht_size;
	lpm = rte_zmalloc_socket("TABLE", total_size, CACHE_LINE_SIZE,
		socket_id);
	if (lpm == NULL) {
		RTE_LOG(ERR, TABLE,
			"%s: Cannot allocate %u bytes for LPM table\n",
			__func__, total_size);
		return NULL;
	}

	/* LPM low-level table creation */
	lpm->lpm = rte_lpm_create("LPM", socket_id, p->n_rules, 0);
	if (lpm->lpm == NULL) {
		rte_free(lpm);
		RTE_LOG(ERR, TABLE, "Unable to create low-level LPM table\n");
		return NULL;
	}

	/* Memory initialization */
	lpm->entry_size = entry_size;
	lpm->entry_unique_size = p->entry_unique_size;
	lpm->n_rules = p->n_rules;
	lpm->offset = p->offset;

	return lpm;
}

int
mg_table_lpm_free(void *table)
{
	struct rte_table_lpm *lpm = (struct rte_table_lpm *) table;
  printf("lpm free: %p\n", lpm);

	/* Check input parameters */
	if (lpm == NULL) {
		RTE_LOG(ERR, TABLE, "%s: table parameter is NULL\n", __func__);
		return -EINVAL;
	}

	/* Free previously allocated resources */
	rte_lpm_free(lpm->lpm);
	rte_free(lpm);

	return 0;
}

static int
nht_find_free(struct rte_table_lpm *lpm, uint32_t *pos)
{
	uint32_t i;

	for (i = 0; i < RTE_TABLE_LPM_MAX_NEXT_HOPS; i++) {
		if (lpm->nht_users[i] == 0) {
			*pos = i;
			return 1;
		}
	}

	return 0;
}

static int
nht_find_existing(struct rte_table_lpm *lpm, void *entry, uint32_t *pos)
{
	uint32_t i;

	for (i = 0; i < RTE_TABLE_LPM_MAX_NEXT_HOPS; i++) {
		uint8_t *nht_entry = &lpm->nht[i * lpm->entry_size];

		if ((lpm->nht_users[i] > 0) && (memcmp(nht_entry, entry,
			lpm->entry_unique_size) == 0)) {
			*pos = i;
			return 1;
		}
	}

	return 0;
}

int
mg_table_entry_add_simple(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry)
{
  //printhex("add ip: ", &ip, 4);
  //printhex("add prefix: ", &depth, 1);
  //printhex("add entry: ", entry, 11);
  int key_found;
  void *entry_ptr;
  return mg_table_lpm_entry_add(table, ip, depth, entry, &key_found, &entry_ptr);
}

int
mg_table_lpm_entry_add(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry,
	int *key_found,
	void **entry_ptr)
{
	struct rte_table_lpm *lpm = (struct rte_table_lpm *) table;
	uint32_t nht_pos, nht_pos0_valid;
	int status;
	uint8_t nht_pos0;

	/* Check input parameters */
	if (lpm == NULL) {
		RTE_LOG(ERR, TABLE, "%s: table parameter is NULL\n", __func__);
		return -EINVAL;
	}
	if (entry == NULL) {
		RTE_LOG(ERR, TABLE, "%s: entry parameter is NULL\n", __func__);
		return -EINVAL;
	}

	if ((depth == 0) || (depth > 32)) {
		RTE_LOG(ERR, TABLE, "%s: invalid depth (%d)\n",
			__func__, depth);
		return -EINVAL;
	}

	/* Check if rule is already present in the table */
	status = rte_lpm_is_rule_present(lpm->lpm, ip,
		depth, &nht_pos0);
	nht_pos0_valid = status > 0;

	/* Find existing or free NHT entry */
	if (nht_find_existing(lpm, entry, &nht_pos) == 0) {
		uint8_t *nht_entry;

		if (nht_find_free(lpm, &nht_pos) == 0) {
			RTE_LOG(ERR, TABLE, "%s: NHT full\n", __func__);
			return -1;
		}

		nht_entry = &lpm->nht[nht_pos * lpm->entry_size];
		memcpy(nht_entry, entry, lpm->entry_size);
	}

	/* Add rule to low level LPM table */
	if (rte_lpm_add(lpm->lpm, ip, depth,
		(uint8_t) nht_pos) < 0) {
		RTE_LOG(ERR, TABLE, "%s: LPM rule add failed\n", __func__);
		return -1;
	}

	/* Commit NHT changes */
	lpm->nht_users[nht_pos]++;
	lpm->nht_users[nht_pos0] -= nht_pos0_valid;

	*key_found = nht_pos0_valid;
	*entry_ptr = (void *) &lpm->nht[nht_pos * lpm->entry_size];
	return 0;
}

int
mg_table_lpm_entry_delete(
	void *table,
  uint32_t ip,
  uint8_t depth,
	int *key_found,
	void *entry)
{
	struct rte_table_lpm *lpm = (struct rte_table_lpm *) table;
	uint8_t nht_pos;
	int status;

	/* Check input parameters */
	if (lpm == NULL) {
		RTE_LOG(ERR, TABLE, "%s: table parameter is NULL\n", __func__);
		return -EINVAL;
	}
	if ((depth == 0) || (depth > 32)) {
		RTE_LOG(ERR, TABLE, "%s: invalid depth (%d)\n", __func__,
			depth);
		return -EINVAL;
	}

	/* Return if rule is not present in the table */
	status = rte_lpm_is_rule_present(lpm->lpm, ip,
		depth, &nht_pos);
	if (status < 0) {
		RTE_LOG(ERR, TABLE, "%s: LPM algorithmic error\n", __func__);
		return -1;
	}
	if (status == 0) {
		*key_found = 0;
		return 0;
	}

	/* Delete rule from the low-level LPM table */
	status = rte_lpm_delete(lpm->lpm, ip, depth);
	if (status) {
		RTE_LOG(ERR, TABLE, "%s: LPM rule delete failed\n", __func__);
		return -1;
	}

	/* Commit NHT changes */
	lpm->nht_users[nht_pos]--;

	*key_found = 1;
	if (entry)
		memcpy(entry, &lpm->nht[nht_pos * lpm->entry_size],
			lpm->entry_size);

	return 0;
}

int mg_table_lpm_lookup_big_burst(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* pkts_mask,
	struct mg_bitmask* lookup_hit_mask,
	void **entries)
{

  uint64_t *in_mask = ((struct mg_bitmask*)(pkts_mask))->mask;
  uint64_t *out_mask = ((struct mg_bitmask*)(lookup_hit_mask))->mask;
  uint16_t n_blocks  = ((struct mg_bitmask*)(pkts_mask))->n_blocks;
  //printf("n_blocks = %d\n", n_blocks);
  uint16_t i;
  for(i=0; i<n_blocks; i++){
    mg_table_lpm_lookup(table, pkts, *in_mask, out_mask, entries);
    //printhex("in_mask_iteration = ", in_mask, 8);
    //printhex("out_mask_iteration = ", out_mask, 8);
    pkts += 64;
    in_mask++;
    out_mask++;
    entries += 64;
  }
  return 0;
}

int
mg_table_lpm_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries)
{
  //printf("ENTRIES = %p\n", entries);
	struct rte_table_lpm *lpm = (struct rte_table_lpm *) table;
	uint64_t pkts_out_mask = 0;
	uint32_t i;

  //struct rte_pktmbuf pkt0 = pkts[0]->pkt;
  //printf("headroom: %d\n", rte_pktmbuf_headroom(pkts[0]));
  ////void * data = pkt0.data+128;
  //void * data = pkt0.data;
  //printhex("data          = ", data, 256);
  //printhex("data buf addr = ", pkts[0]->buf_addr, 256);
  //printhex("pktinmask = ", &pkts_mask, 8);
  //printhex("ipaddr = ", pkts[0]->buf_addr + lpm->offset, 4);

	pkts_out_mask = 0;
  if(!pkts_mask){
    // workaround for DPDK bug:
    // __builtin_clzll(x) is undefined for x = 0
    *lookup_hit_mask = pkts_out_mask;
    return 0;
  }
	for (i = 0; i < (uint32_t)(RTE_PORT_IN_BURST_SIZE_MAX -
		__builtin_clzll(pkts_mask)); i++) {
    //printf("loop %d\n", i);
		uint64_t pkt_mask = 1LLU << i;

		if (pkt_mask & pkts_mask) {
      //printf("pktmaskmatch\n");
			struct rte_mbuf *pkt = pkts[i];
			//uint32_t ip = rte_bswap32(
			//	*((uint32_t*)(&RTE_MBUF_METADATA_UINT8(pkt, lpm->offset))));
			uint32_t ip = rte_bswap32( *((uint32_t*)(pkt->buf_addr + lpm->offset)) );
			//uint32_t ip = ( *((uint32_t*)(pkt->buf_addr + lpm->offset)) );
      //printhex("checking ip: ", &ip, 4);
			int status;
			uint8_t nht_pos;

			status = rte_lpm_lookup(lpm->lpm, ip, &nht_pos);
      //printf(" status: %d\n", status);
			if (status == 0) {
        //printf("HIT HIT HIT\n");
				pkts_out_mask |= pkt_mask;
				entries[i] = (void *) &lpm->nht[nht_pos *
					lpm->entry_size];
      }else{
        entries[i] = NULL;
      }
      //printf("r: entries[%d\t] = %p\n", i, entries[i]);
      //printf("r: entries pp[%d\t] = %p\n", i, entries+i);
      //printf("r: entries[%d\t] = %p\n", i, *(entries+i));
      //printf("  iface = %d\n", ((uint8_t*)(entries[i]))[4]);
		}
    // FIXME: if input mask does not match should we also set entry ptr to NULL?
	}

	*lookup_hit_mask = pkts_out_mask;

	return 0;
}

int mg_table_lpm_apply_route(
	struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
	void **entries,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size)
{
  uint16_t i;
  for(i=0;i<pkts_mask->size;i++){
    if(mg_bitmask_get_bit(pkts_mask, i)){
      // TODO: check if just 6 byte direct assignment is faster here (more parallel)
      // TODO: we could also do this in LUA, check if performance is affected...
      // TODO: we could also do this already on lookup. Check if performance is affected
      // copy data to packet
      //rte_memcpy((*pkts)->buf_addr + offset_pkt, *entries + offset_entry, size);
      
      struct ether_hdr * ethhdr = rte_pktmbuf_mtod(*pkts, struct ether_hdr *);
      ether_addr_copy((struct ether_addr*)(*entries + offset_entry), &ethhdr->d_addr);
    }
    pkts++;
    entries++;
  }
  return 0;
}

void ** mg_lpm_table_allocate_entry_prts(uint16_t n_entries){
  return (void**)(rte_malloc(NULL, sizeof(void*)*n_entries, 0));
}

//int mg_lpm_table_lookup(
//	void *table,
//	struct rte_mbuf **pkts,
//	uint64_t pkts_mask,
//	//uint64_t *lookup_hit_mask,
//  struct mg_lpm4_routes * routes)
//{
//  struct rte_pktmbuf pkt0 = pkts[0]->pkt;
//  printf("headroom: %d\n", rte_pktmbuf_headroom(pkts[0]));
//  //void * data = pkt0.data+128;
//  void * data = pkt0.data;
//  int i;
//  printf("data = \n");
//  for(i=0;i<256;i++){
//    printf("%2x ", ((uint8_t*)data)[i]);
//  }
//  printf("\n");
//
//  // FIXME: XXX: pkts_mask hardcoded to 1 for debugging
//  int result = rte_table_lpm_ops.f_lookup(table, pkts, 1, &routes->hit_mask, &(routes->entries));
//  printf("hit mask c : ");
//  printhex(&routes->hit_mask, 8);
//  printf("C result entry[0]: ");
//  printhex(&routes->entries[0], 5);
//
//  return result;
//}

