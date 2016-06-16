---------------------------------
--- @file dpdkc.lua
--- @brief DPDKc ...
--- @todo TODO docu
---------------------------------

--- low-level dpdk wrapper
local ffi = require "ffi"

-- structs
ffi.cdef[[
	// core management
	enum rte_lcore_state_t {
		WAIT, RUNNING, FINISHED
	};

	

	// packets/mbufs
	
	struct mempool {
	}; // dummy struct, only needed to associate it with a metatable

	typedef void    *MARKER[0];
	typedef void    *MARKER_CACHE_ALIGNED[0] __attribute__((aligned(64)));
	typedef uint8_t  MARKER8[0];
	typedef uint64_t MARKER64[0];
	
	struct rte_mbuf;
	union rte_ipsec {
		uint32_t data;
		//struct {
		//	uint16_t sa_idx:10;
		//	uint16_t esp_len:9;
		//	uint8_t type:1;
		//	uint8_t mode:1;
		//	uint16_t unused:11; /**< These 11 bits are unused. */
		//} sec;
	};

	struct rte_mbuf {
		MARKER cacheline0;

		void *buf_addr;           /**< Virtual address of segment buffer. */
		void *buf_physaddr; /**< Physical address of segment buffer. */

		uint16_t buf_len;         /**< Length of segment buffer. */

		/* next 6 bytes are initialised on RX descriptor rearm */
		MARKER8 rearm_data;
		uint16_t data_off;

		uint16_t refcnt;
		uint8_t nb_segs;          /**< Number of segments. */
		uint8_t port;             /**< Input port. */

		uint64_t ol_flags;        /**< Offload features. */
		/* remaining bytes are set on RX when pulling packet from descriptor */
		MARKER rx_descriptor_fields1;

		/*
		* The packet type, which is the combination of outer/inner L2, L3, L4
		* and tunnel types.
		 */
		uint32_t packet_type; /**< L2/L3/L4 and tunnel information. */

		uint32_t pkt_len;         /**< Total pkt len: sum of all segments. */
		uint16_t data_len;        /**< Amount of data in segment buffer. */
		uint16_t vlan_tci;        /**< VLAN Tag Control Identifier (CPU order) */

		union {
			uint32_t rss;     /**< RSS hash result if RSS enabled */
			struct {
				union {
					struct {
						uint16_t hash;
						uint16_t id;
					};
					uint32_t lo;
					/**< Second 4 flexible bytes */
				};
				uint32_t hi;
				/**< First 4 flexible bytes or FD ID, dependent on
			     PKT_RX_FDIR_* flag in ol_flags. */
			} fdir;           /**< Filter identifier if FDIR enabled */
			struct {
				uint32_t lo;
				uint32_t hi;
			} sched;          /**< Hierarchical scheduler */
			uint32_t usr;	  /**< User defined tags. See rte_distributor_process() */
		} hash;                   /**< hash information */

		uint32_t seqn; /**< Sequence number. See also rte_reorder_insert() */

		uint16_t vlan_tci_outer;  /**< Outer VLAN Tag Control Identifier (CPU order) */

		/* second cache line - fields only used in slow path or on TX */
		MARKER_CACHE_ALIGNED cacheline1;

		uint64_t udata64;

		struct rte_mempool *pool; /**< Pool from which mbuf was allocated. */
		struct rte_mbuf *next;    /**< Next segment of scattered packet. */

		/* fields to support TX offloads */
		uint64_t tx_offload;

		/** Size of the application private data. In case of an indirect
		 * mbuf, it stores the direct mbuf private data size. */
		uint16_t priv_size;

		/** Timesync flags for use with IEEE1588. */
		uint16_t timesync;

		/* Chain of off-load operations to perform on mbuf */
		struct rte_mbuf_offload *offload_ops;
	};

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
	enum rte_l4type {
		RTE_FDIR_L4TYPE_NONE = 0,       /**< None. */
		RTE_FDIR_L4TYPE_UDP,            /**< UDP. */
		RTE_FDIR_L4TYPE_TCP,            /**< TCP. */
		RTE_FDIR_L4TYPE_SCTP,           /**< SCTP. */
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


	// statistics
	struct rte_eth_stats {
		uint64_t ipackets;  /**< Total number of successfully received packets. */
		uint64_t opackets;  /**< Total number of successfully transmitted packets.*/
		uint64_t ibytes;    /**< Total number of successfully received bytes. */
		uint64_t obytes;    /**< Total number of successfully transmitted bytes. */
		uint64_t imissed;   /**< Total of RX missed packets (e.g full FIFO). */
		uint64_t ibadcrc;   /**< Total of RX packets with CRC error. */
		uint64_t ibadlen;   /**< Total of RX packets with bad length. */
		uint64_t ierrors;   /**< Total number of erroneous received packets. */
		uint64_t oerrors;   /**< Total number of failed transmitted packets. */
		uint64_t imcasts;   /**< Total number of multicast received packets. */
		uint64_t rx_nombuf; /**< Total number of RX mbuf allocation failures. */
		uint64_t fdirmatch; /**< Total number of RX packets matching a filter. */
		uint64_t fdirmiss;  /**< Total number of RX packets not matching any filter. */
		uint64_t tx_pause_xon;  /**< Total nb. of XON pause frame sent. */
		uint64_t rx_pause_xon;  /**< Total nb. of XON pause frame received. */
		uint64_t tx_pause_xoff; /**< Total nb. of XOFF pause frame sent. */
		uint64_t rx_pause_xoff; /**< Total nb. of XOFF pause frame received. */
		// TODO: 16 is a dpdk compile-time constant which kind of sucks. probably needs a rewrite or something.
		uint64_t q_ipackets[16];
		/**< Total number of queue RX packets. */
		uint64_t q_opackets[16];
		/**< Total number of queue TX packets. */
		uint64_t q_ibytes[16];
		/**< Total number of successfully received queue bytes. */
		uint64_t q_obytes[16];
		/**< Total number of successfully transmitted queue bytes. */
		uint64_t q_errors[16];
		/**< Total number of queue packets received that are dropped. */
		uint64_t ilbpackets;
		/**< Total number of good packets received from loopback,VF Only */
		uint64_t olbpackets;
		/**< Total number of good packets transmitted to loopback,VF Only */
		uint64_t ilbbytes;
		/**< Total number of good bytes received from loopback,VF Only */
		uint64_t olbbytes;
		/**< Total number of good bytes transmitted to loopback,VF Only */
	};

  struct mg_rss_hash_mask{
    uint8_t ipv4 :1;
    uint8_t tcp_ipv4 :1;
    uint8_t udp_ipv4 :1;
    uint8_t ipv6 :1;
    uint8_t tcp_ipv6 :1;
    uint8_t udp_ipv6 :1;
  };
]]

-- dpdk functions and wrappers
ffi.cdef[[
	// eal init
	int rte_eal_init(int argc, const char* argv[]); 
	
	// cpu core management
	int rte_eal_get_lcore_state(int core);
	enum rte_lcore_state_t rte_eal_get_lcore_state(unsigned int slave_id);
	int rte_eal_wait_lcore(int core);
	uint32_t get_current_core();
	uint32_t get_current_socket();

	// memory
	struct mempool* init_mem(uint32_t nb_mbuf, uint32_t sock, uint32_t mbuf_size);
	struct rte_mbuf* alloc_mbuf(struct mempool* mp);
	void alloc_mbufs(struct mempool* mp, struct rte_mbuf* bufs[], uint32_t len, uint16_t pkt_len);
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
	int configure_device(int port, int rx_queues, int tx_queues, int rx_descs, int tx_descs, uint16_t link_speed, struct mempool* mempool, bool drop_en, uint8_t rss_enable, struct mg_rss_hash_mask * hash_functions, bool disable_offloads, bool is_i40e_device, bool strip_vlan, bool disable_padding);
	void get_mac_addr(int port, char* buf);
	uint32_t get_pci_id(uint8_t port);
	uint32_t read_reg32(uint8_t port, uint32_t reg);
	uint64_t read_reg64(uint8_t port, uint32_t reg);
	void write_reg32(uint8_t port, uint32_t reg, uint32_t val);
	void write_reg64(uint8_t port, uint32_t reg, uint64_t val);
	void sync_clocks(uint8_t port1, uint8_t port2, uint32_t timl, uint32_t timh, uint32_t adjl, uint32_t adjh);
	int32_t get_clock_difference(uint8_t port1, uint8_t port2, uint32_t timl, uint32_t timh);
	uint8_t get_socket(uint8_t port);
	void rte_eth_promiscuous_enable(uint8_t port);
	void rte_eth_promiscuous_disable(uint8_t port);
	void* get_eth_dev(int port);
	void* get_i40e_dev(int port);
	int get_i40e_vsi_seid(int port);
	uint8_t get_pci_function(uint8_t port);
	int rte_eth_dev_mac_addr_add(uint8_t port, void* mac, uint32_t pool);
	int rte_eth_dev_mac_addr_remove(uint8_t port, void* mac);
	int get_max_ports();

	// rx & tx
	uint16_t rte_eth_rx_burst_export(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** rx_pkts, uint16_t nb_pkts);
	uint16_t rte_eth_tx_burst_export(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** tx_pkts, uint16_t nb_pkts);
	int rte_eth_dev_tx_queue_start(uint8_t port_id, uint16_t rx_queue_id);
	int rte_eth_dev_tx_queue_stop(uint8_t port_id, uint16_t rx_queue_id);
	void send_all_packets(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** pkts, uint16_t num_pkts);
	void send_all_packets_with_delay_invalid_size(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct mempool* pool);
	void send_all_packets_with_delay_bad_crc(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct mempool* pool, uint32_t min_pkt_size);
	void send_packet_with_timestamp(uint8_t port_id, uint16_t queue_id, struct rte_mbuf* pkt, uint16_t offs);
	uint16_t receive_with_timestamps_software(uint8_t port_id, uint16_t queue_id, void* rx_pkts, uint16_t nb_pkts, uint64_t timestamps[]);
	uint64_t get_bad_pkts_sent(uint8_t port_id);
	uint64_t get_bad_bytes_sent(uint8_t port_id);

	// fdir filter
	int rte_eth_dev_fdir_add_perfect_filter(uint8_t port_id, struct rte_fdir_filter* fdir_filter, uint16_t soft_id, uint8_t rx_queue, uint8_t drop);	
	int rte_eth_dev_fdir_set_masks(uint8_t port_id, struct rte_fdir_masks* fdir_mask);

	
	// checksum offloading
	void calc_ipv4_pseudo_header_checksum(void* data, int offset);
	void calc_ipv4_pseudo_header_checksums(struct rte_mbuf** pkts, uint16_t num_pkts, int offset);
	void calc_ipv6_pseudo_header_checksum(void* data, int offset);
	void calc_ipv6_pseudo_header_checksums(struct rte_mbuf** pkts, uint16_t num_pkts, int offset);

	// timers
	void rte_delay_ms_export(uint32_t ms);
	void rte_delay_us_export(uint32_t us);
	uint64_t rte_rdtsc();
	uint64_t rte_get_tsc_hz();

	// lifecycle
	uint8_t is_running(uint32_t extra_time);
	void set_runtime(uint32_t ms);

	// timestamping
	void read_timestamps_software(uint8_t port_id, uint16_t queue_id, uint32_t* data, uint64_t size);

	// statistics
	void rte_eth_stats_get(uint8_t port, struct rte_eth_stats* stats);
]]

return ffi.C

