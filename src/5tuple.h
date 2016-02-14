#ifndef __INCLUDE_MG_5TUPLE_H__
#define __INCLUDE_MG_5TUPLE_H__

#include <stdint.h>
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>
#include "bitmask.h"

struct mg_5tuple_ipv4_5tuple {
    uint8_t proto;
    uint32_t ip_src;
    uint32_t ip_dst;
    uint16_t port_src;
    uint16_t port_dst;
};

struct mg_5tuple_rule {
    uint8_t proto;
    uint32_t ip_src;
    uint8_t ip_src_prefix;
    uint32_t ip_dst;
    uint8_t ip_dst_prefix;
    uint16_t port_src;
    uint16_t port_src_range;
    uint16_t port_dst;
    uint16_t port_dst_range;

};

// Functions for the software 5tuple filter
struct rte_acl_ctx * mg_5tuple_create_filter(int socket_id, uint32_t num_rules);
void mg_5tuple_destruct_filter(struct rte_acl_ctx * acl);
int mg_5tuple_add_rule(struct rte_acl_ctx * acx, struct mg_5tuple_rule * mgrule, int32_t priority, uint32_t category_mask, uint32_t value);
int mg_5tuple_build_filter(struct rte_acl_ctx * acx, uint32_t num_categories);
int mg_5tuple_classify_burst(
    struct rte_acl_ctx * acx,
    struct rte_mbuf **pkts,
    struct mg_bitmask* pkts_mask,
    uint32_t num_categories,
    uint32_t num_real_categories,
    struct mg_bitmask** result_masks,
    uint32_t ** result_entries
    );
uint32_t mg_5tuple_get_results_multiplier();

// Functions for the hardware 5tuple filter
int mg_5tuple_add_HWfilter_ixgbe(uint8_t port_id, uint16_t index,
			struct rte_5tuple_filter *filter, uint16_t rx_queue);
#endif

