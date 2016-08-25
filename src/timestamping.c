#include <stdint.h>
#include <inttypes.h>

#include <rte_config.h>
#include <rte_ethdev.h> 
#include <rte_mempool.h>
#include <rte_mbuf.h>
#include <rte_cycles.h>

#include "rdtsc.h"
#include "lifecycle.h"

// FIXME: link speed is hardcoded to 10gbit (but not really relevant for this use case where you should have only one packet anyways)
// this is only optimized for latency measurements/timestamping, not packet capture
// packet capturing would benefit from running the whole rx thread in C to avoid gc/jit pauses
uint16_t receive_with_timestamps_software(uint8_t port_id, uint16_t queue_id, struct rte_mbuf* rx_pkts[], uint16_t nb_pkts, uint64_t timestamps[]) {
	uint32_t cycles_per_byte = rte_get_tsc_hz() / 10000000.0 / 0.8;
	while (is_running()) {
		uint64_t tsc = read_rdtsc();
		uint16_t rx = rte_eth_rx_burst(port_id, queue_id, rx_pkts, nb_pkts);
		uint16_t prev_pkt_size = 0;
		for (int i = 0; i < rx; i++) {
			timestamps[i] = tsc + prev_pkt_size * cycles_per_byte;
			prev_pkt_size = rx_pkts[i]->pkt_len + 24;
		}
		if (rx > 0) {
			return rx;
		}
	}
	return 0;
}

