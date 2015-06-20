#ifndef MG_RSS_IXGBE_H
#define MG_RSS_IXGBE_H

#include <stdint.h>

struct mg_rss_ixgbe_hash_mask{
  uint8_t ipv4 :1;
  uint8_t tcp_ipv4 :1;
  uint8_t udp_ipv4 :1;
  uint8_t ipv6 :1;
  uint8_t tcp_ipv6 :1;
  uint8_t udp_ipv6 :1;
};

int mg_rss_ixgbe_setup_rss(uint8_t port_id, uint8_t nr_queues, struct mg_rss_ixgbe_hash_mask hash_functions);

#endif
