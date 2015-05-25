#include "5tuple.h"


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

void mg_5tuple_add_rule(struct rte_acl_ctx * acx, struct mg_5tuple_rule * mgrule, int32_t priority, uint32_t category_mask, uint32_t value){
  // FIXME: stack or heap?
  struct acl_ipv4_rule acl_rules[1];
  rule[0].data.userdata = value;
  rule[0].data.category_mask = category_mask;
  rule[0].data.priority = priority;
  rule[0].field[0].value = mgrule.proto;
  rule[0].field[0].mask = 0xff;
  rule[0].field[1].value = mgrule.ip_src;
  rule[0].field[1].mask = mgrule.ip_src_mask;
  rule[0].field[2].value = mgrule.ip_dst;
  rule[0].field[2].mask = mgrule.ip_dst_mask;
  rule[0].field[3].value = mgrule.port_src;
  rule[0].field[3].mask = mgrule.port_src_range;
  rule[0].field[4].value = mgrule.port_dst;
  rule[0].field[4].mask = mgrule.port_dst_range;


  return rte_acl_add_rules(acx, acl_rules, RTE_DIM(acl_rules));
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
    uint16_t n,
    struct mg_bitmask* pkts_mask,
    //FIXME: what will be the result?
    ){


}

