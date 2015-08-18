#ifndef MG_DEVICE_H
#define MG_DEVICE_H
#include <stdint.h>

struct mg_rss_hash_mask{
  uint8_t ipv4 :1;
  uint8_t tcp_ipv4 :1;
  uint8_t udp_ipv4 :1;
  uint8_t ipv6 :1;
  uint8_t tcp_ipv6 :1;
  uint8_t udp_ipv6 :1;
};


#endif
