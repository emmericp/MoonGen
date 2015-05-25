#include "5tuple.h"
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_acl.h>
#include <rte_ip.h>
#include <rte_ether.h>

#include "bitmask.h"
#include "debug.h"

#define OFF_ETHHEAD	(sizeof(struct ether_hdr))
#define OFF_IPV42PROTO (offsetof(struct ipv4_hdr, next_proto_id))
#define MBUF_IPV4_2PROTO(m)	\
	(rte_pktmbuf_mtod((m), uint8_t *) + OFF_ETHHEAD + OFF_IPV42PROTO)

enum {
	PROTO_FIELD_IPV4,
	SRC_FIELD_IPV4,
	DST_FIELD_IPV4,
	SRCP_FIELD_IPV4,
	DSTP_FIELD_IPV4,
	NUM_FIELDS_IPV4
};

// data is expected to start from the Protocol field in the IP header
struct rte_acl_field_def ipv4_defs[NUM_FIELDS_IPV4] = {
	{
		.type = RTE_ACL_FIELD_TYPE_BITMASK,
		.size = sizeof(uint8_t),
		.field_index = PROTO_FIELD_IPV4,
		.input_index = RTE_ACL_IPV4VLAN_PROTO,
		.offset = 0,
	},
	{
		.type = RTE_ACL_FIELD_TYPE_MASK,
		.size = sizeof(uint32_t),
		.field_index = SRC_FIELD_IPV4,
		.input_index = RTE_ACL_IPV4VLAN_SRC,
		.offset = offsetof(struct ipv4_hdr, src_addr) -
			offsetof(struct ipv4_hdr, next_proto_id),
	},
	{
		.type = RTE_ACL_FIELD_TYPE_MASK,
		.size = sizeof(uint32_t),
		.field_index = DST_FIELD_IPV4,
		.input_index = RTE_ACL_IPV4VLAN_DST,
		.offset = offsetof(struct ipv4_hdr, dst_addr) -
			offsetof(struct ipv4_hdr, next_proto_id),
	},
	{
		.type = RTE_ACL_FIELD_TYPE_RANGE,
		.size = sizeof(uint16_t),
		.field_index = SRCP_FIELD_IPV4,
		.input_index = RTE_ACL_IPV4VLAN_PORTS,
		.offset = sizeof(struct ipv4_hdr) -
			offsetof(struct ipv4_hdr, next_proto_id),
	},
	{
		.type = RTE_ACL_FIELD_TYPE_RANGE,
		.size = sizeof(uint16_t),
		.field_index = DSTP_FIELD_IPV4,
		.input_index = RTE_ACL_IPV4VLAN_PORTS,
		.offset = sizeof(struct ipv4_hdr) -
			offsetof(struct ipv4_hdr, next_proto_id) +
			sizeof(uint16_t),
	},
};

// This defines a strucuture "struct acl_ipv4_rule"
RTE_ACL_RULE_DEF(acl_ipv4_rule, RTE_DIM(ipv4_defs));

struct rte_acl_ctx * mg_5tuple_create_filter(int socket_id, uint32_t num_rules){

  // FIXME: is prm on stack OK? or does this have to be on HEAP?
  struct rte_acl_param prm = {
      .name = "ACL_5tuple_filter",
      .socket_id = socket_id,
      .rule_size = RTE_ACL_RULE_SZ(RTE_DIM(ipv4_defs)),
      /* number of fields per rule. */
      .max_rule_num = num_rules, /* maximum number of rules in the AC context. */
  };

  return rte_acl_create(&prm);
}

void mg_5tuple_destruct_filter(struct rte_acl_ctx * acl){
  rte_acl_free(acl);
}

int mg_5tuple_add_rule(struct rte_acl_ctx * acx, struct mg_5tuple_rule * mgrule, int32_t priority, uint32_t category_mask, uint32_t value){
  // FIXME: stack or heap?
  struct acl_ipv4_rule acl_rules[1];
  acl_rules[0].data.userdata = value;
  acl_rules[0].data.category_mask = category_mask;
  acl_rules[0].data.priority = priority;
  acl_rules[0].field[0].value.u8 = mgrule->proto;
  acl_rules[0].field[0].mask_range.u8 = 0xff;
  acl_rules[0].field[1].value.u32 = mgrule->ip_src;
  acl_rules[0].field[1].mask_range.u32 = mgrule->ip_src_prefix;
  acl_rules[0].field[2].value.u32 = mgrule->ip_dst;
  acl_rules[0].field[2].mask_range.u32 = mgrule->ip_dst_prefix;
  acl_rules[0].field[3].value.u16 = mgrule->port_src;
  acl_rules[0].field[3].mask_range.u16 = mgrule->port_src_range;
  acl_rules[0].field[4].value.u16 = mgrule->port_dst;
  acl_rules[0].field[4].mask_range.u16 = mgrule->port_dst_range;


  return rte_acl_add_rules(acx, (struct rte_acl_rule *)(acl_rules), RTE_DIM(acl_rules));
}

int mg_5tuple_build_filter(struct rte_acl_ctx * acx, uint32_t num_categories){
  struct rte_acl_config cfg;
  cfg.num_categories = num_categories;
  cfg.num_fields = RTE_DIM(ipv4_defs);
  memcpy(cfg.defs, ipv4_defs, sizeof(ipv4_defs));
  return rte_acl_build(acx, &cfg);
}


int mg_5tuple_classify_burst(
    struct rte_acl_ctx * acx,
    struct rte_mbuf **pkts,
    struct mg_bitmask* pkts_mask,
    uint32_t num_categories,
    struct mg_bitmask** result_masks,
    uint32_t ** result_entries
    //FIXME: what will be the result?
    ){

  uint16_t i;
  // FIXME what does const here mean?
  const uint8_t * data[pkts_mask->size];

  // compress:
  uint16_t n_real=0;
  for(i=0;i<pkts_mask->size;i++){
    if(mg_bitmask_get_bit(pkts_mask, i)){
      data[n_real] = MBUF_IPV4_2PROTO(pkts[i]);
      n_real++;
    }
  }

  // compute results:
  uint32_t results[num_categories * n_real];
  rte_acl_classify(acx, data, results, n_real, num_categories);

  // decompress:
  //uint32_t c;
  //for(c=0; c< categories; c++){
  //  n_real = 0;
  //  for(i=0;i<pkts_mask.size;i++){
  //    if(mg_bitmask_get_bit(pkts_mask, i)){
  //      uint32_t result = results[n_real*categories + c];
  //      result_entries[c][i] = result;
  //      if(result){
  //        mg_bitmask_set_bit(result_masks[c], i);
  //      }
  //      n_real++;
  //    }
  //  }
  //}
  

  // decompress:
  uint32_t category = 0;
  uint16_t packet = 0;
  for(i= 0; i< num_categories*n_real; i++){
    if(category == num_categories){
      category = 0;
      packet++;
      while( mg_bitmask_get_bit(pkts_mask, packet) == 0){
        packet++;
      }
    }
    if(results[i]){
      mg_bitmask_set_bit(result_masks[category], packet);
    }
    result_entries[category][packet] = results[i];
    category++;
  }
  return 0;
}

