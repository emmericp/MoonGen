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

#define DEFAULT_MTU 8000

static volatile uint8_t* registers[RTE_MAX_ETHPORTS];

uint32_t read_reg32(uint8_t port, uint32_t reg) {
	return *(volatile uint32_t*)(registers[port] + reg);
}

void write_reg32(uint8_t port, uint32_t reg, uint32_t val) {
	*(volatile uint32_t*)(registers[port] + reg) = val;
}

static inline volatile uint32_t* get_reg_addr(uint8_t port, uint32_t reg) {
	return (volatile uint32_t*)(registers[port] + reg);
}

int configure_device(int port, int rx_queues, int tx_queues, int rx_descs, int tx_descs, struct rte_mempool* mempool) {
	if (port >= RTE_MAX_ETHPORTS) {
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
	// allow sending large and small frames
	rte_eth_dev_set_mtu(port, DEFAULT_MTU);
	uint32_t hlReg0 = read_reg32(port, 0x4240);
	hlReg0 &= ~(1 << 10); // TXPADEN
	hlReg0 |= (1 << 2); // JUMBOEN
	write_reg32(port, 0x4240, hlReg0);
	return rc; 
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
	struct rte_eth_dev_info dev_info;
	rte_eth_dev_info_get(port, &dev_info);
	int node = dev_info.pci_dev->numa_node;
	if (node == -1) {
		node = 0;
	}
	return (uint8_t) node;
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

// software rate control

static uint64_t bad_pkts_sent[RTE_MAX_ETHPORTS];
static uint64_t bad_bytes_sent[RTE_MAX_ETHPORTS];

uint64_t get_bad_pkts_sent(uint8_t port_id) {
	return __sync_fetch_and_and(&bad_pkts_sent[port_id], 0);
}

uint64_t get_bad_bytes_sent(uint8_t port_id) {
	return __sync_fetch_and_and(&bad_bytes_sent[port_id], 0);
}

// TODO: figure out which NICs can actually transmit short frames, currently tested:
// NIC      Min Frame Length (including CRC, preamble, SFD, and IFG, i.e. a regular Ethernet frame would be 84 bytes)
// X540		76
// 82599	76
// TODO: does not yet work with jumboframe-enabled DuTs, use a different delay mechanism for this use case
static struct rte_mbuf* get_delay_pkt_invalid_size(struct rte_mempool* pool, uint32_t* rem_delay) {
	uint32_t delay = *rem_delay;
	// TODO: this is actually wrong for most NICs, fix this
	if (delay < 25) {
		// smaller than the smallest packet we can send
		// (which is preamble + SFD + CRC + IFG + 1 byte)
		// the CRC cannot be avoided since the CRC offload cannot be disabled on a per-packet basis
		// TODO: keep a counter of the error so that the average rate is correct
		*rem_delay = 25; // will be set to 0 at the end of the function
		delay = 25;
	}
	// calculate the optimimum packet size
	if (delay < 84) {
		// simplest case: requested gap smaller than the minimum allowed size
		// nothing to do
	} else if (delay > 1542) { // includes vlan tag to play it safe
		// remaining delay larger than the maximum frame size
		if (delay >= 1543 * 2) {
			// we could use even larger frames but this would be annoying (chained buffers or larger mbufs required)
			delay = 1543;
			// remaining size after this packet is still > 1514
		} else {
			// remaining size can be sent in a single packet
		}
	} else {
		// valid packet size, use lots of small packets
		if (delay - 83 < 25) {
			// next packet would be too small, i.e. remaining delay is between 64 and 89 bytes
			// this means we can just send two packets with remaining_delay/2 size
			delay = delay / 2;
		} else {
			delay = 83;
		}
	}
	*rem_delay -= delay;
	// TODO: consider allocating these packets at the beginning for performance reasons
	struct rte_mbuf* pkt = rte_pktmbuf_alloc(pool);
	// account for CRC offloading
	pkt->pkt.data_len = delay - 24;
	pkt->pkt.pkt_len = delay - 24;
	//printf("%d\n", delay - 24);
	return pkt;
}

void send_all_packets_with_delay_invalid_size(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct rte_mempool* pool) {
	const int BUF_SIZE = 128;
	struct rte_mbuf* pkts[BUF_SIZE];
	int send_buf_idx = 0;
	uint32_t num_bad_pkts = 0;
	uint32_t num_bad_bytes = 0;
	for (uint16_t i = 0; i < num_pkts; i++) {
		struct rte_mbuf* pkt = load_pkts[i];
		// desired inter-frame spacing is encoded in the hash field (not used on TX packets)
		// it would also be possible to use the buffer's headroom but this is ugly from Lua
		// TODO: this can be changed to the new userdata or udata64 fields in DPDK 1.8
		uint32_t delay = pkt->pkt.hash.rss;
		// step 1: generate delay-packets
		while (delay > 0) {
			struct rte_mbuf* pkt = get_delay_pkt_invalid_size(pool, &delay);
			if (pkt) {
				num_bad_pkts++;
				// packet size: [MAC, CRC] to be consistent with HW counters
				num_bad_bytes += pkt->pkt.pkt_len + 4;
				pkts[send_buf_idx++] = pkt;
			}
			if (send_buf_idx >= BUF_SIZE) {
				send_all_packets(port_id, queue_id, pkts, send_buf_idx);
				send_buf_idx = 0;
			}
		}
		// step 2: send the packet
		pkts[send_buf_idx++] = pkt;
		if (send_buf_idx >= BUF_SIZE || i + 1 == num_pkts) { // don't forget to send the last batch
			send_all_packets(port_id, queue_id, pkts, send_buf_idx);
			send_buf_idx = 0;
		}
	}
	__sync_fetch_and_add(&bad_pkts_sent[port_id], num_bad_pkts);
	__sync_fetch_and_add(&bad_bytes_sent[port_id], num_bad_bytes);
	return;
}

// FIXME: not thread safe!
static struct rte_mbuf* get_delay_pkt_bad_crc(struct rte_mempool* pool, uint32_t* rem_delay) {
 	// FIXME: these should be thread-local
	static uint32_t target = 0;
	static uint32_t current = 0;
	uint32_t delay = *rem_delay;
	target += delay;
	if (target < current) {
		// don't add a delay
		*rem_delay = 0;
		return NULL;
	}
	// add delay
	target -= current;
	current = 0;
	if (delay < 76) {
		// TODO: figure out min sizes for different NICs, this is tested for X540 and 82599
		// smaller than the smallest packet we can send
		*rem_delay = 76; // will be set to 0 at the end of the function
		delay = 76;
	}
	// calculate the optimimum packet size
	if (delay < 1538) {
		delay = delay;
	} else if (delay > 2000) {
		// 2000 is an arbitrary chosen value as it doesn't really matter
		// we just need to avoid doing something stupid for packet sizes that are just over 1538 bytes
		delay = 1538;
	} else {
		// delay between 1538 and 2000
		delay = delay / 2;
	}
	*rem_delay -= delay;
	struct rte_mbuf* pkt = rte_pktmbuf_alloc(pool);
	// account for preamble, sfd, and ifg (CRC is disabled)
	pkt->pkt.data_len = delay - 20;
	pkt->pkt.pkt_len = delay - 20;
	pkt->ol_flags |= PKT_TX_NO_CRC_CSUM;
	current += delay;
	return pkt;
}


// NOTE: this function only works on ixgbe-based NICs as it relies on a driver modification allow disabling CRC on a per-packet basis
void send_all_packets_with_delay_bad_crc(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct rte_mempool* pool) {
	const int BUF_SIZE = 128;
	struct rte_mbuf* pkts[BUF_SIZE];
	int send_buf_idx = 0;
	uint32_t num_bad_pkts = 0;
	uint32_t num_bad_bytes = 0;
	for (uint16_t i = 0; i < num_pkts; i++) {
		struct rte_mbuf* pkt = load_pkts[i];
		// desired inter-frame spacing is encoded in the hash field (not used on TX packets)
		// it would also be possible to use the buffer's headroom but this is ugly from Lua
		// TODO: this can be changed to the new userdata or udata64 fields in DPDK 1.8
		uint32_t delay = pkt->pkt.hash.rss;
		// step 1: generate delay-packets
		while (delay > 0) {
			struct rte_mbuf* pkt = get_delay_pkt_bad_crc(pool, &delay);
			if (pkt) {
				num_bad_pkts++;
				// packet size: [MAC, CRC] to be consistent with HW counters
				num_bad_bytes += pkt->pkt.pkt_len;
				pkts[send_buf_idx++] = pkt;
			}
			if (send_buf_idx >= BUF_SIZE) {
				send_all_packets(port_id, queue_id, pkts, send_buf_idx);
				send_buf_idx = 0;
			}
		}
		// step 2: send the packet
		pkts[send_buf_idx++] = pkt;
		if (send_buf_idx >= BUF_SIZE || i + 1 == num_pkts) { // don't forget to send the last batch
			send_all_packets(port_id, queue_id, pkts, send_buf_idx);
			send_buf_idx = 0;
		}
	}
	// atomic as multiple threads may use the same stats register from multiple queues
	__sync_fetch_and_add(&bad_pkts_sent[port_id], num_bad_pkts);
	__sync_fetch_and_add(&bad_bytes_sent[port_id], num_bad_bytes);
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
