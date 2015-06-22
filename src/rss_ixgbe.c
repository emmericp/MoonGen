#include <rte_config.h>
#include <rte_common.h>
#include <rte_ethdev.h>
#include "rss_ixgbe.h"
#include "ixgbe_ethdev.h"
#include "ixgbe/ixgbe_type.h"


int mg_rss_ixgbe_setup_rss(uint8_t port_id, uint8_t nr_queues, struct mg_rss_ixgbe_hash_mask hash_functions){
  struct rte_eth_dev *dev;

  printf("init rss: port_id = %u, nr_queues = %u\n",port_id, nr_queues);
	if (port_id >= rte_eth_dev_count()) {
		printf("Invalid port_id=%d\n", port_id);
		return -ENODEV;
	}
  dev = &rte_eth_devices[port_id];
  struct ixgbe_hw *hw = IXGBE_DEV_PRIVATE_TO_HW(dev->data->dev_private);

  // fill the redirection table:
  uint8_t n_unique = 32/nr_queues;
  uint8_t i;
  uint32_t queue = 0;
  for(i= 0; i<32; i++){
    uint32_t reta = queue | (queue << 8) | (queue << 16) | (queue << 24);
    IXGBE_WRITE_REG(hw, IXGBE_RETA(i), reta);
    if((i%n_unique == 0) && (i != 0)){
      queue++;
    }
  }
  
  // This is already abstracted by dpdk.

  // uint32_t mrqc;
  // // enable rss:
  // mrqc = IXGBE_MRQC_RSSEN;

  // // configure the selected hash functions:
  // if(hash_functions.ipv4){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV4;
  //   printf("ipv4\n");
  // }
  // if(hash_functions.udp_ipv4){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV4_UDP;
  //   printf("ipv4 udp\n");
  // }
  // if(hash_functions.tcp_ipv4){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV4_TCP;
  //   printf("ipv4 tcp\n");
  // }
  // if(hash_functions.ipv6){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV6;
  //   printf("ipv6\n");
  // }
  // if(hash_functions.udp_ipv6){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV6_TCP;
  //   printf("ipv6 udp\n");
  // }
  // if(hash_functions.tcp_ipv6){
  //   mrqc |= IXGBE_MRQC_RSS_FIELD_IPV6_UDP;
  //   printf("ipv6 tcp\n");
  // }

	// IXGBE_WRITE_REG(hw, IXGBE_MRQC, mrqc);

  return 0;
}
