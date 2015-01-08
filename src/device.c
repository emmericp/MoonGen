#include <rte_config.h>
#include <rte_ethdev.h> 
#include <rte_mempool.h>
#include <rte_ether.h>
#include <rte_cycles.h>
#include <rte_mbuf.h>
#include <ixgbe_type.h>
#include <rte_mbuf.h>

// default descriptors per queue
#define DEFAULT_RX_DESCS 512
#define DEFAULT_TX_DESCS 256

// values taken from the DPDK-L2FWD example, optimized for 82599 chips
#define RX_PTHRESH 8
#define RX_HTHRESH 8
#define RX_WTHRESH 4
#define TX_PTHRESH 36
#define TX_HTHRESH 0
#define TX_WTHRESH 0

#define MAX_ETH_DEVICES 64
static uint8_t* registers[RTE_MAX_ETHPORTS];

int configure_device(int port, int rx_queues, int tx_queues, int rx_descs, int tx_descs, struct rte_mempool* mempool) {
	if (port > RTE_MAX_ETHPORTS) {
		printf("error: Maximum number of supported ports is %d\n   This can be changed with the DPDK compile-time configuration variable RTE_MAX_ETHPORTS\n", RTE_MAX_ETHPORTS);
		return -1;
	}
	// TODO: enable other FDIR filter types
	struct rte_fdir_conf fdir_conf = {
		.mode = RTE_FDIR_MODE_PERFECT,
		.pballoc = RTE_FDIR_PBALLOC_64K,
		.status = RTE_FDIR_REPORT_STATUS_ALWAYS,
		.flexbytes_offset = 21, // TODO support other values
		.drop_queue = 63, // TODO: support for other NICs
	};
	struct rte_eth_conf port_conf = {
		.rxmode = {
			.split_hdr_size = 0,
			.header_split = 0,
			.hw_ip_checksum = 1,
			.hw_vlan_filter = 0,
			.jumbo_frame = 0,
			.hw_strip_crc = 1,
		},
		.txmode = {
			.mq_mode = ETH_MQ_TX_NONE,
		},
		.fdir_conf = fdir_conf,
	};
	int rc = rte_eth_dev_configure(port, rx_queues, tx_queues, &port_conf);
	if (rc) return rc;
	// DPDK documentation suggests that the tx queues should be set up before the rx queues
	struct rte_eth_txconf tx_conf = {
		// TODO: this should use different values for older GbE NICs
		.tx_thresh = {
			.pthresh = TX_PTHRESH,
			.hthresh = TX_HTHRESH,
			.wthresh = TX_WTHRESH,
		},
		.tx_free_thresh = 0, // 0 = default
		.tx_rs_thresh = 0, // 0 = default
		.txq_flags = ETH_TXQ_FLAGS_NOMULTSEGS,
	};
	for (int i = 0; i < tx_queues; i++) {
		// TODO: get socket id for the NIC
		rc = rte_eth_tx_queue_setup(port, i, tx_descs ? tx_descs : DEFAULT_TX_DESCS, SOCKET_ID_ANY, &tx_conf);
		if (rc) {
			printf("could not configure tx queue %d\n", i);
			return rc;
		}
	}
	struct rte_eth_rxconf rx_conf = {
		.rx_drop_en = 1, // TODO: make this configurable per queue
		.rx_thresh = {
			.pthresh = RX_PTHRESH,
			.hthresh = RX_HTHRESH,
			.wthresh = RX_WTHRESH,
		},
	};
	for (int i = 0; i < rx_queues; i++) {
		// TODO: get socket id for the NIC
		rc = rte_eth_rx_queue_setup(port, i, rx_descs ? rx_descs : DEFAULT_RX_DESCS, SOCKET_ID_ANY, &rx_conf, mempool);
		if (rc) {
			printf("could not configure rx queue %d\n", i);
			return rc;
		}
	}
	rte_eth_promiscuous_enable(port);
	rc = rte_eth_dev_start(port);
	// save memory address of the register file
	struct rte_eth_dev_info dev_info;
	rte_eth_dev_info_get(port, &dev_info);
	registers[port] = (uint8_t*) dev_info.pci_dev->mem_resource[0].addr;
	return rc; 
}

uint32_t read_reg32(uint8_t port, uint32_t reg) {
	return *(volatile uint32_t*)(registers[port] + reg);
}

void write_reg32(uint8_t port, uint32_t reg, uint32_t val) {
	//printf("write_reg32(%u, %u, %u)\n", port, reg, val);
	*(volatile uint32_t*)(registers[port] + reg) = val;
}

static inline volatile uint32_t* get_reg_addr(uint8_t port, uint32_t reg) {
	return (volatile uint32_t*)(registers[port] + reg);
}

uint64_t get_mac_addr(int port, char* buf) {
	struct ether_addr addr;
	rte_eth_macaddr_get(port, &addr);
	if (buf) {
		sprintf(buf, "%02X:%02X:%02X:%02X:%02X:%02X", addr.addr_bytes[0], addr.addr_bytes[1], addr.addr_bytes[2], addr.addr_bytes[3], addr.addr_bytes[4], addr.addr_bytes[5]);
	}
	return addr.addr_bytes[0] | (addr.addr_bytes[1] << 8) | (addr.addr_bytes[2] << 16) | ((uint64_t) addr.addr_bytes[3] << 24) | ((uint64_t) addr.addr_bytes[4] << 32) | ((uint64_t) addr.addr_bytes[5] << 40);
}

uint32_t get_pci_id(uint8_t port) {
	struct rte_eth_dev_info dev_info;
	rte_eth_dev_info_get(port, &dev_info);
	return dev_info.pci_dev->id.vendor_id << 16 | dev_info.pci_dev->id.device_id;
}

uint8_t get_socket(uint8_t port) {
	// TODO: figure out to get this information
	return 0;
}

void sync_clocks(uint8_t port1, uint8_t port2) {
	// resetting SYSTIML twice prevents a race-condition when SYSTIML is just about to overflow into SYSTIMH
	write_reg32(port1, IXGBE_SYSTIML, 0);
	write_reg32(port2, IXGBE_SYSTIML, 0);
	write_reg32(port1, IXGBE_SYSTIMH, 0);
	write_reg32(port2, IXGBE_SYSTIMH, 0);
	if (port1 == port2) {
		// just reset timers if port1 == port2
		return;
	}
	// to avoid potential unnecessary overhead between the two accesses; especially if compiler optimizations are disabled for some reason
	// this is probably completely unnecessary on a modern OoO cpu
	volatile uint32_t* port1time = get_reg_addr(port1, IXGBE_SYSTIML);
	volatile uint32_t* port2time = get_reg_addr(port2, IXGBE_SYSTIML);
	const int num_runs = 7; // must be odd
	int32_t offsets[num_runs];
	*port1time = 0;
	*port2time = 0; // the clocks now differ by offs, the time for the write access which is calculated in the following loop
	for (int i = 0; i < num_runs; i++) {
		uint32_t x1 = *port1time;
		uint32_t x2 = *port2time;
		uint32_t y1 = *port2time;
		uint32_t y2 = *port1time;
		int32_t delta_t = abs(((int64_t) x1 - x2 - ((int64_t) y2 - y1)) / 2); // time between two reads
		int32_t offs = delta_t + x1 - x2;
		offsets[i] = offs;
		//printf("%d: delta_t: %d\toffs: %d\n", i, delta_t, offs);
	}
	int cmp(const void* e1, const void* e2) {
		int32_t offs1 = *(int32_t*) e1;
		int32_t offs2 = *(int32_t*) e2;
		return offs1 < offs2 ? -1 : offs1 > offs2 ? 1 : 0;
	}
	// use the median offset
	qsort(offsets, num_runs, sizeof(int32_t), &cmp);
	int32_t offs = offsets[num_runs / 2];
	if (offs) {
		// offs of 0 is not supported
		write_reg32(port2, IXGBE_TIMADJL, offs < 0 ? (uint32_t) -offs : (uint32_t) offs);
		write_reg32(port2, IXGBE_TIMADJH, offs < 0 ? 1 << 31 : 0);
		// verification that the clocks are synced: the two clocks should only differ by a constant caused by the read operation
		// i.e. x2 - x1 = y2 - y1 iff clock1 == clock2
		/*uint32_t x1 = *port1time;
		uint32_t x2 = *port2time;
		uint32_t y1 = *port2time;
		uint32_t y2 = *port1time;
		printf("%d %d\n", x2 - x1, y2 - y1);*/
	}
}

// for calibration
uint32_t get_clock_difference(uint8_t port1, uint8_t port2) {
	// TODO: this should take the delay between reading the two registers into account
	// however, this is not necessary for the current use case (measuring clock drift)
	volatile uint32_t p1time = read_reg32(port1, IXGBE_SYSTIML);
	volatile uint32_t p2time = read_reg32(port2, IXGBE_SYSTIML);
	volatile uint32_t p1timeh = read_reg32(port1, IXGBE_SYSTIMH);
	volatile uint32_t p2timeh = read_reg32(port2, IXGBE_SYSTIMH);
	return (((int64_t) p1timeh << 32) | p1time) - (((int64_t) p2timeh << 32) | p2time);
}

void send_all_packets(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** pkts, uint16_t num_pkts) {
	uint32_t sent = 0;
	while (1) {
		sent += rte_eth_tx_burst(port_id, queue_id, pkts + sent, num_pkts - sent);
		if (sent >= num_pkts) {
			return;
		}
	}
	return;
}

void send_all_packets_with_delay_invalid_mac(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** pkts, uint16_t num_pkts, uint32_t* delays, struct rte_mempool* pool) {
	struct rte_mbuf* delay_pkt;
	for (uint16_t i = 0; i < num_pkts; i++) {
		delay_pkt = rte_pktmbuf_alloc(pool);
		delay_pkt->pkt.data_len = delays[i];
		delay_pkt->pkt.pkt_len = delays[i];
		while (!rte_eth_tx_burst(port_id, queue_id, &delay_pkt, 1));
		while (!rte_eth_tx_burst(port_id, queue_id, pkts + i, 1));
	}
	return;
}

// registers all libraries
// this should be done on startup via a __attribute__((__constructor__)) function
// however, there seems to be a bug: the init functions don't seem to work if called in the wrong order (note that the order depends on the linker)
// calling devinitfn_bond_drv() last causes problems
// so we just add them here again in an order that actually works independent from the link order
void devinitfn_rte_vmxnet3_driver();
void devinitfn_rte_virtio_driver();
void devinitfn_pmd_ring_drv();
void devinitfn_rte_ixgbe_driver();
void devinitfn_rte_ixgbevf_driver();
void devinitfn_rte_i40evf_driver();
void devinitfn_rte_i40e_driver();
void devinitfn_pmd_igb_drv();
void devinitfn_pmd_igbvf_drv();
void devinitfn_em_pmd_drv();
void devinitfn_bond_drv();
void devinitfn_pmd_xenvirt_drv();
void devinitfn_pmd_pcap_drv();
void register_pmd_drivers() {
	devinitfn_bond_drv();
	devinitfn_rte_vmxnet3_driver();
	devinitfn_rte_virtio_driver();
	devinitfn_pmd_ring_drv();
	devinitfn_rte_ixgbevf_driver();
	devinitfn_rte_ixgbe_driver();
	devinitfn_rte_i40evf_driver();
	devinitfn_rte_i40e_driver();
	devinitfn_pmd_igb_drv();
	devinitfn_pmd_igbvf_drv();
	devinitfn_em_pmd_drv();
	// TODO: what's wrong with these two?
	//devinitfn_pmd_xenvirt_drv();
	//devinitfn_pmd_pcap_drv();
}

// the following functions are static inline function in header files
// this is the easiest/least ugly way to make them available to luajit (#defining static before including the header breaks stuff)
uint16_t rte_eth_rx_burst_export(uint8_t port_id, uint16_t queue_id, void* rx_pkts, uint16_t nb_pkts) {
	return rte_eth_rx_burst(port_id, queue_id, rx_pkts, nb_pkts);
}

uint16_t rte_eth_tx_burst_export(uint8_t port_id, uint16_t queue_id, void* tx_pkts, uint16_t nb_pkts) {
	return rte_eth_tx_burst(port_id, queue_id, tx_pkts, nb_pkts);
}

void rte_pktmbuf_free_export(void* m) {
	rte_pktmbuf_free(m);
}


void rte_delay_ms_export(uint32_t ms) {
	rte_delay_ms(ms);
}

void rte_delay_us_export(uint32_t us) {
	rte_delay_us(us);
}
