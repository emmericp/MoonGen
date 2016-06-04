#include <stdio.h>
#include <string.h>
#include <rte_config.h>
#include <rte_common.h>
#include <rte_mempool.h>
#include <rte_mbuf.h>
#include <rte_kni.h>
#include <rte_pci.h>
#include <rte_ethdev.h>
#include <stdint.h>

/* Max size of a single packet */
#define MAX_PACKET_SZ           2048

static int kni_change_mtu(uint8_t port_id, unsigned new_mtu){
  printf("change mtu\n");
  return 0;
}
static int kni_config_network_interface(uint8_t port_id, uint8_t if_up){
  printf("interface config\n");
  return 0;
}

//struct rte_kni * mg_create_kni(uint8_t port_id, uint8_t core_id, struct rte_mempool* pktmbuf_pool){
struct rte_kni * mg_create_kni(uint8_t port_id, uint8_t core_id, void* mempool_ptr, const char name[]){
  //printf("create kni\n");
  //printf("mempool ptr 1 : %p\n", mempool_ptr);
  struct rte_kni *kni;
	struct rte_kni_conf conf;
  /* Clear conf at first */
  memset(&conf, 0, sizeof(conf));
  snprintf(conf.name, RTE_KNI_NAMESIZE, "%s", name);
  conf.core_id = core_id;
  conf.force_bind = 1;
  conf.group_id = (uint16_t)port_id;
  conf.mbuf_size = MAX_PACKET_SZ;

  struct rte_eth_dev_info dev_info;

  memset(&dev_info, 0, sizeof(dev_info));
  //printf("get dev info\n");
  rte_eth_dev_info_get(port_id, &dev_info);
  //printf("dev done\n");
  //printf("pci dev: %p\n", dev_info.pci_dev);
  conf.addr = dev_info.pci_dev->addr;
  //printf("a\n");
  conf.id = dev_info.pci_dev->id;
  //printf("b\n");

  struct rte_kni_ops ops;
  //printf("c\n");
  memset(&ops, 0, sizeof(ops));
  //printf("d\n");
  ops.port_id = port_id;
  //printf("e\n");
  ops.change_mtu = kni_change_mtu;
  //printf("f\n");
  ops.config_network_if = kni_config_network_interface;

  //printf("alloc\n");
  struct rte_mempool * pktmbuf_pool = (struct rte_mempool *)(mempool_ptr);
  //printf("mempool pointer: %p\n", pktmbuf_pool);
  kni = rte_kni_alloc(pktmbuf_pool, &conf, &ops);
  //printf("done, kni = %p\n", kni);

  //rte_eth_dev_start(port_id);
  return kni;
}

unsigned mg_kni_tx_single(struct rte_kni * kni, struct rte_mbuf * mbuf){
  return rte_kni_tx_burst(kni, &mbuf, 1);
}
