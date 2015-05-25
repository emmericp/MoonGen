#ifndef __INCLUDE_MG_5TUPLE_H__
#define __INCLUDE_MG_5TUPLE_H__

#include <stdint.h>

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
#endif

