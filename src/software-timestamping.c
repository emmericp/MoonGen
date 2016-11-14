#include <stdint.h>

#include <rte_config.h>
#include <rte_ethdev.h> 
#include <rte_mempool.h>
#include <rte_mbuf.h>
#include <rte_cycles.h>

#include "rdtsc.h"
#include "lifecycle.h"

// software timestamping
void moongen_send_packet_with_timestamp(uint8_t port_id, uint16_t queue_id, struct rte_mbuf* pkt, uint16_t offs) {
	while (is_running(0)) {
		rte_pktmbuf_mtod_offset(pkt, uint64_t*, 0)[offs] = read_rdtsc();
		if (rte_eth_tx_burst(port_id, queue_id, &pkt, 1) == 1) {
			return;
		}
	}
}

