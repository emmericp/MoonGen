#include <stdint.h>
#include <inttypes.h>

#include <rte_config.h>
#include <rte_ethdev.h> 
#include <rte_mempool.h>
#include <rte_mbuf.h>

#include "rdtsc.h"
#include "lifecycle.h"

static const size_t BURST_SIZE = 512;

void read_timestamps_software(uint8_t port_id, uint16_t queue_id, uint32_t* data, uint64_t size) {

	struct rte_mbuf* rx_pkts[BURST_SIZE];
	uint64_t data_counter = 0, old_tsc = 0, tsc = 0;
	uint16_t nb_rx = 0;

	// flush old packets from rx_queue
	rte_eth_rx_burst(port_id, queue_id, rx_pkts, BURST_SIZE);

	while (data_counter < size && is_running()) {
		nb_rx = rte_eth_rx_burst(port_id, queue_id, rx_pkts, BURST_SIZE);
		if (nb_rx > 0) {
			tsc = read_rdtsc();
			for (uint64_t i = 0; i < nb_rx; i++) {
				data[++data_counter] = (uint32_t) (tsc - old_tsc);
				rte_pktmbuf_free(rx_pkts[i]);
				//printf("tsc: %"PRIu64, tsc);
				//printf("\notsc: %"PRIu64, old_tsc);
				//printf("\ndiff: %d\n", data[data_counter-1]);
				old_tsc = tsc;
			}
		}

	}

	//FIXME preliminary output
	for (uint64_t i = 0; i < 4096; i++) {
		printf("%d\n", data[i]);
	}
}

