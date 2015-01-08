--- low-level dpdk wrapper
local ffi = require "ffi"

-- structs
ffi.cdef[[
	// core management
	enum rte_lcore_state_t {
		WAIT, RUNNING, FINISHED
	};

	// packets/mbufs
	struct rte_pktmbuf {
		struct rte_mbuf* next;
		void* data;
		uint16_t data_len;
		uint8_t nb_segs;
		uint8_t in_port;
		uint32_t pkt_len;
		//union {
		uint16_t header_lengths;
		uint16_t vlan_tci;
		//uint32_t value;
		//} offsets;
		union {
			uint32_t rss;
			struct {
				uint16_t hash;
				uint16_t id;
			} fdir;
			uint32_t sched;
		} hash;
	};

	struct rte_mbuf {
		void* pool;
		void* data;
		uint64_t phy_addr;
		uint16_t len;
		uint16_t refcnt;
		uint8_t type;
		uint8_t reserved;
		uint16_t ol_flags;
		struct rte_pktmbuf pkt;
	};

	struct mempool {
	}; // dummy struct, only needed to associate it with a metatable
	
	// device status/info
	struct rte_eth_link {
		uint16_t link_speed;
		uint16_t link_duplex;
		uint8_t link_status: 1;
	} __attribute__((aligned(8)));

	struct rte_fdir_filter {
		uint16_t flex_bytes;
		uint16_t vlan_id;
		uint16_t port_src;
		uint16_t port_dst;
		union {
			uint32_t ipv4_addr;
			uint32_t ipv6_addr[4];
		} ip_src;
		union {
			uint32_t ipv4_addr;
			uint32_t ipv6_addr[4];
		} ip_dst;
		int l4type;
		int iptype;
	};


	struct rte_fdir_masks {
		uint8_t only_ip_flow;
		uint8_t vlan_id;
		uint8_t vlan_prio;
		uint8_t flexbytes;
		uint8_t set_ipv6_mask;
		uint8_t comp_ipv6_dst;
		uint32_t dst_ipv4_mask;
		uint32_t src_ipv4_mask;
		uint16_t dst_ipv6_mask;
		uint16_t src_ipv6_mask;
		uint16_t src_port_mask;
		uint16_t dst_port_mask;
	};
]]

-- dpdk functions and wrappers
ffi.cdef[[
	// eal init
	int rte_eal_init(int argc, const char* argv[]); 
	
	// cpu core management
	int rte_eal_get_lcore_state(int core);
	enum rte_lcore_state_t rte_eal_get_lcore_state(unsigned int slave_id);

	// memory
	struct mempool* init_mem(uint32_t nb_mbuf, int32_t sock);
	struct rte_mbuf* alloc_mbuf(struct mempool* mp);
	void rte_pktmbuf_free_export(struct rte_mbuf* m);
	uint16_t rte_mbuf_refcnt_read_export(struct rte_mbuf* m);
	uint16_t rte_mbuf_refcnt_update_export(struct rte_mbuf* m, int16_t value);

	// devices
	void register_pmd_drivers();
	int rte_eal_pci_probe();
	int rte_eth_dev_count();
	uint64_t get_mac_addr(int port, char* buf);
	void rte_eth_link_get(uint8_t port, struct rte_eth_link* link);
	void rte_eth_link_get_nowait(uint8_t port, struct rte_eth_link* link);
	int configure_device(int port, int rx_queues, int tx_queues, int rx_descs, int tx_descs, struct mempool* mempool);
	void get_mac_addr(int port, char* buf);
	uint32_t get_pci_id(uint8_t port);
	uint32_t read_reg32(uint8_t port, uint32_t reg);
	void write_reg32(uint8_t port, uint32_t reg, uint32_t val);
	void sync_clocks(uint8_t port1, uint8_t port2);
	int32_t get_clock_difference(uint8_t port1, uint8_t port2);
	uint8_t get_socket(uint8_t port);
	void rte_eth_promiscuous_enable(uint8_t port);
	void rte_eth_promiscuous_disable(uint8_t port);

	// rx & tx
	uint16_t rte_eth_rx_burst_export(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** rx_pkts, uint16_t nb_pkts);
	uint16_t rte_eth_tx_burst_export(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** tx_pkts, uint16_t nb_pkts);
	void send_all_packets(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** pkts, uint16_t num_pkts);
	void send_all_packets_with_delay_invalid_mac(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** pkts, uint16_t num_pkts, uint32_t* delays, struct mempool* pool);

	// fdir filter
	int rte_eth_dev_fdir_add_perfect_filter(uint8_t port_id, struct rte_fdir_filter* fdir_filter, uint16_t soft_id, uint8_t rx_queue, uint8_t drop);	
	int rte_eth_dev_fdir_set_masks(uint8_t port_id, struct rte_fdir_masks* fdir_mask);

	
	// checksum offloading
	void calc_ipv4_pseudo_header_checksum(void* data);
	void calc_ipv4_pseudo_header_checksums(struct rte_mbuf** pkts, uint16_t num_pkts);
	void calc_ipv6_pseudo_header_checksum(void* data);
	void calc_ipv6_pseudo_header_checksums(struct rte_mbuf** pkts, uint16_t num_pkts);

	// timers
	void rte_delay_ms_export(uint32_t ms);
	void rte_delay_us_export(uint32_t us);
	uint64_t rte_rdtsc();
	uint64_t rte_get_tsc_hz();

	// lifecycle
	uint8_t is_running();
	void set_runtime(uint32_t ms);

	// timestamping
	void read_timestamps_software(uint8_t port_id, uint16_t queue_id, uint32_t* data, uint64_t size);
]]

return ffi.C

