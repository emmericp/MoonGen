#include "5tuple.h"
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mbuf.h>
#include <rte_acl.h>
#include <rte_ip.h>
#include <rte_ether.h>

#include "bitmask.h"
#include "debug.h"

// FIXME: tidy up this include mess
// I had trouble locating all the macros needed
// for the mg_5tuple_add_HWfilter_ixgbe function.
//----
#include <sys/types.h>
#include <sys/queue.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <stdint.h>
#include <inttypes.h>

#include <rte_byteorder.h>
#include <rte_log.h>
#include <rte_debug.h>
#include <rte_interrupts.h>
#include <rte_pci.h>
#include <rte_memory.h>
#include <rte_memcpy.h>
#include <rte_memzone.h>
#include <rte_launch.h>
#include <rte_tailq.h>
#include <rte_eal.h>
#include <rte_per_lcore.h>
#include <rte_lcore.h>
#include <rte_atomic.h>
#include <rte_branch_prediction.h>
#include <rte_common.h>
#include <rte_ring.h>
#include <rte_mempool.h>
#include <rte_malloc.h>
#include <rte_mbuf.h>
#include <rte_errno.h>
#include <rte_spinlock.h>
#include <rte_string_fns.h>

#include "rte_ether.h"
#include "rte_ethdev.h"

//----
#include <sys/queue.h>
#include <stdio.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h>
#include <inttypes.h>
#include <rte_byteorder.h>
#include <rte_common.h>
#include <rte_cycles.h>

#include <rte_interrupts.h>
#include <rte_log.h>
#include <rte_debug.h>
#include <rte_pci.h>
#include <rte_atomic.h>
#include <rte_branch_prediction.h>
#include <rte_memory.h>
#include <rte_memzone.h>
#include <rte_tailq.h>
#include <rte_eal.h>
#include <rte_alarm.h>
#include <rte_ether.h>
#include <rte_ethdev.h>
#include <rte_atomic.h>
#include <rte_malloc.h>
#include <rte_random.h>
#include <rte_dev.h>

#include "ixgbe_api.h"
#include "ixgbe_vf.h"
#include "ixgbe_common.h"
#include "ixgbe_ethdev.h"
#include "ixgbe_bypass.h"
#include "ixgbe_rxtx.h"

#ifdef RTE_LIBRTE_ETHDEV_DEBUG
#define PMD_DEBUG_TRACE(fmt, args...) do {                        \
		RTE_LOG(ERR, PMD, "%s: " fmt, __func__, ## args); \
	} while (0)
#else
#define PMD_DEBUG_TRACE(fmt, args...)
#endif

/* Macros to check for invlaid function pointers in dev_ops structure */
#define FUNC_PTR_OR_ERR_RET(func, retval) do { \
	if ((func) == NULL) { \
		PMD_DEBUG_TRACE("Function not supported\n"); \
		return (retval); \
	} \
} while(0)
#define FUNC_PTR_OR_RET(func) do { \
	if ((func) == NULL) { \
		PMD_DEBUG_TRACE("Function not supported\n"); \
		return; \
	} \
} while(0)


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
  printf("add mask = %x\n", category_mask);
  printf("add value = %u\n", value);
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
  printf("build: num_categories = %d\n", num_categories);
  cfg.num_categories = num_categories;
  cfg.num_fields = RTE_DIM(ipv4_defs);
  memcpy(cfg.defs, ipv4_defs, sizeof(ipv4_defs));
  return rte_acl_build(acx, &cfg);
}

uint32_t mg_5tuple_get_results_multiplier(){
  return RTE_ACL_RESULTS_MULTIPLIER;
}

int mg_5tuple_classify_burst(
    struct rte_acl_ctx * acx,
    struct rte_mbuf **pkts,
    struct mg_bitmask* pkts_mask,
    uint32_t num_categories,
    uint32_t num_real_categories,
    struct mg_bitmask** result_masks,
    uint32_t ** result_entries
    //FIXME: what will be the result?
    ){

  printf("classify start\n");
  uint16_t i;
  // FIXME what does const here mean?
  const uint8_t * data[pkts_mask->size];

  printf("compress\n");
  // compress:
  uint16_t n_real=0;
  for(i=0;i<pkts_mask->size;i++){
    if(mg_bitmask_get_bit(pkts_mask, i)){
      data[n_real] = MBUF_IPV4_2PROTO(pkts[i]);
      n_real++;
    }
  }

  printf("compute\n");
  // compute results:
  uint32_t results[num_categories * n_real];
  int status = rte_acl_classify(acx, data, results, n_real, num_categories);
  printf("status = %d\n", status);
  printf("multiplier: %lu\n", RTE_ACL_RESULTS_MULTIPLIER);
  printf("maxCat: %d\n", RTE_ACL_MAX_CATEGORIES);

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
  printf("num_categories = %d\n", num_categories);
  
  printf("results:\n");
  for (i=0;i<num_categories*n_real;i++){
    printf(" %u", results[i]);
    if (i%2 == 1){
      printf("| ");
    }
  }
  printf("\n");

  // decompress:
  printf("decompress\n");
  printf("n_real = %d\n", n_real);
  uint32_t category = 0;
  uint16_t packet = 0;
  for(i= 0; i< num_categories*n_real; i++){
    printf(" i = %d\n", i);
    printf(" category = %d\n", category);
    printf(" packet = %d\n", packet);
    if(category == num_categories){
      category = 0;
      packet++;
      while( mg_bitmask_get_bit(pkts_mask, packet) == 0){
        printf("  skip\n");
        packet++;
      }
    }
    if(category < num_real_categories){
      if(results[i]){
        printf("  set bit\n");
        mg_bitmask_set_bit(result_masks[category], packet);
      }
      printf("access entries\n");
      result_entries[category][packet] = results[i];
    }
    category++;
  }
  printf("return\n");
  return status;
}


int
mg_5tuple_add_HWfilter_ixgbe(uint8_t port_id, uint16_t index,
			struct rte_5tuple_filter *filter, uint16_t rx_queue)
{
  //printf("add filter: port_id = %u, index = %u, queue = %u\n", port_id, index, rx_queue);
  //printf("mask = %u, %u, %u, %u, %u\n", filter->dst_ip_mask, filter->src_ip_mask, filter->dst_port_mask, filter->src_port_mask, filter->protocol_mask);
  //printhex("filter: ", filter, 21);

  // the following code is merged from dpdk version 1.x and 2.0
  // as the version shipped with moongen (1.x) has not yet implemented
  // support for 5tuple filters on x540 NICs
  // NOTE: this function overrides most device compatibility checks and assumes
  // a x540 or similar NIC
	struct rte_eth_dev *dev;

	if (port_id >= rte_eth_dev_count()) {
		PMD_DEBUG_TRACE("Invalid port_id=%d\n", port_id);
		return -ENODEV;
	}

	if (filter->protocol != IPPROTO_TCP &&
		filter->tcp_flags != 0){
		PMD_DEBUG_TRACE("tcp flags is 0x%x, but the protocol value"
			" is not TCP\n",
			filter->tcp_flags);
		return -EINVAL;
	}

  uint8_t protocol = 0x3;
  switch (filter->protocol){
    case IPPROTO_TCP:
      protocol = 0x0;
      break;
    case IPPROTO_UDP:
      protocol = 0x1;
      break;
    case IPPROTO_SCTP:
      protocol = 0x2;
      break;
  }

  if(filter->tcp_flags != 0){
		PMD_DEBUG_TRACE("tcp flags not supported in filter\n",);
		return -EINVAL;
  }

	dev = &rte_eth_devices[port_id];

  // I leave this check, as it will sort out some not supported cards...
	FUNC_PTR_OR_ERR_RET(*dev->dev_ops->add_5tuple_filter, -ENOTSUP);

  // XXX the following is hard coded network card specific code
  //  this will (hopefully) work for ixgbe cards.
  // TODO: find a safe way to check, if this code works on the selected NIC
  // XXX: Best solution would be to write a patch for ixgbe_ethdev.c
	struct ixgbe_hw *hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);
	//struct ixgbe_filter_info *filter_info =
	//	IXGBE_DEV_PRIVATE_TO_FILTER_INFO(dev->data->dev_private);
	int i;
	uint32_t ftqf, sdpqf;
	uint32_t l34timir = 0;
	uint8_t mask = 0xff;

  i = index;
  sdpqf = (uint32_t)(filter->dst_port <<
      IXGBE_SDPQF_DSTPORT_SHIFT);
	sdpqf = sdpqf | (filter->src_port & IXGBE_SDPQF_SRCPORT);

	ftqf = (uint32_t)(protocol &
		IXGBE_FTQF_PROTOCOL_MASK);
	ftqf |= (uint32_t)((filter->priority &
		IXGBE_FTQF_PRIORITY_MASK) << IXGBE_FTQF_PRIORITY_SHIFT);
	if (filter->src_ip_mask == 0) /* 0 means compare. */
		mask &= IXGBE_FTQF_SOURCE_ADDR_MASK;
	if (filter->dst_ip_mask == 0)
		mask &= IXGBE_FTQF_DEST_ADDR_MASK;
	if (filter->src_port_mask == 0)
		mask &= IXGBE_FTQF_SOURCE_PORT_MASK;
	if (filter->dst_port_mask == 0)
		mask &= IXGBE_FTQF_DEST_PORT_MASK;
	if (filter->protocol_mask == 0)
		mask &= IXGBE_FTQF_PROTOCOL_COMP_MASK;
	ftqf |= mask << IXGBE_FTQF_5TUPLE_MASK_SHIFT;
	ftqf |= IXGBE_FTQF_POOL_MASK_EN;
	ftqf |= IXGBE_FTQF_QUEUE_ENABLE;

	IXGBE_WRITE_REG(hw, IXGBE_DAQF(i), filter->dst_ip);
	IXGBE_WRITE_REG(hw, IXGBE_SAQF(i), filter->src_ip);
	IXGBE_WRITE_REG(hw, IXGBE_SDPQF(i), sdpqf);
	IXGBE_WRITE_REG(hw, IXGBE_FTQF(i), ftqf);

	l34timir |= IXGBE_L34T_IMIR_RESERVE;
	l34timir |= (uint32_t)(rx_queue <<
				IXGBE_L34T_IMIR_QUEUE_SHIFT);
	IXGBE_WRITE_REG(hw, IXGBE_L34T_IMIR(i), l34timir);

  return 0;
}

// static int
// ixgbe_add_5tuple_filter(struct rte_eth_dev *dev, uint16_t index,
// 			struct rte_5tuple_filter *filter, uint16_t rx_queue)
// {
// 	struct ixgbe_hw *hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);
// 	uint32_t ftqf, sdpqf = 0;
// 	uint32_t l34timir = 0;
// 	uint8_t mask = 0xff;
// 
// 	if (hw->mac.type != ixgbe_mac_82599EB)
// 		return -ENOSYS;
// 
// 	if (index >= IXGBE_MAX_FTQF_FILTERS ||
// 		rx_queue >= IXGBE_MAX_RX_QUEUE_NUM ||
// 		filter->priority > IXGBE_5TUPLE_MAX_PRI ||
// 		filter->priority < IXGBE_5TUPLE_MIN_PRI)
// 		return -EINVAL;  /* filter index is out of range. */
// 
// 	if (filter->tcp_flags) {
// 		PMD_INIT_LOG(INFO, "82599EB not tcp flags in 5tuple");
// 		return -EINVAL;
// 	}
// 
// 	ftqf = IXGBE_READ_REG(hw, IXGBE_FTQF(index));
// 	if (ftqf & IXGBE_FTQF_QUEUE_ENABLE)
// 		return -EINVAL;  /* filter index is in use. */
// 
// 	ftqf = 0;
// 	sdpqf = (uint32_t)(filter->dst_port << IXGBE_SDPQF_DSTPORT_SHIFT);
// 	sdpqf = sdpqf | (filter->src_port & IXGBE_SDPQF_SRCPORT);
// 
// 	ftqf |= (uint32_t)(convert_protocol_type(filter->protocol) &
// 		IXGBE_FTQF_PROTOCOL_MASK);
// 	ftqf |= (uint32_t)((filter->priority & IXGBE_FTQF_PRIORITY_MASK) <<
// 		IXGBE_FTQF_PRIORITY_SHIFT);
// 	if (filter->src_ip_mask == 0) /* 0 means compare. */
// 		mask &= IXGBE_FTQF_SOURCE_ADDR_MASK;
// 	if (filter->dst_ip_mask == 0)
// 		mask &= IXGBE_FTQF_DEST_ADDR_MASK;
// 	if (filter->src_port_mask == 0)
// 		mask &= IXGBE_FTQF_SOURCE_PORT_MASK;
// 	if (filter->dst_port_mask == 0)
// 		mask &= IXGBE_FTQF_DEST_PORT_MASK;
// 	if (filter->protocol_mask == 0)
// 		mask &= IXGBE_FTQF_PROTOCOL_COMP_MASK;
// 	ftqf |= mask << IXGBE_FTQF_5TUPLE_MASK_SHIFT;
// 	ftqf |= IXGBE_FTQF_POOL_MASK_EN;
// 	ftqf |= IXGBE_FTQF_QUEUE_ENABLE;
// 
// 	IXGBE_WRITE_REG(hw, IXGBE_DAQF(index), filter->dst_ip);
// 	IXGBE_WRITE_REG(hw, IXGBE_SAQF(index), filter->src_ip);
// 	IXGBE_WRITE_REG(hw, IXGBE_SDPQF(index), sdpqf);
// 	IXGBE_WRITE_REG(hw, IXGBE_FTQF(index), ftqf);
// 
// 	l34timir |= IXGBE_L34T_IMIR_RESERVE;
// 	l34timir |= (uint32_t)(rx_queue << IXGBE_L34T_IMIR_QUEUE_SHIFT);
// 	IXGBE_WRITE_REG(hw, IXGBE_L34T_IMIR(index), l34timir);
// 	return 0;
// }
