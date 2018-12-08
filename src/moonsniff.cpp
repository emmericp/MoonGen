#include <cstdint>
#include <string>
#include <iostream>
#include <mutex>
#include <fstream>

#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include "lifecycle.hpp"

#define UINT24_MAX 16777215
#define INDEX_MASK (uint32_t) 0x00FFFFFF


/*
 * This namespace holds functions which are used by MoonSniff's Live Mode
 *
 * Other modes are implemented in examples/moonsniff/
 */
namespace moonsniff {
	// values smaller than thresh are ignored
	int64_t thresh = 0; // default: ignore all negative measurements

	// vars for live average computation
	uint64_t count = 0;
	double m2 = 0;
	double mean = 0;
	double variance = 0;

	/**
	 * Statistics which are exposed to applications
	 */
	struct ms_stats {
		int64_t average_latency = 0;
		int64_t variance_latency = 0;
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t inval_ts = 0;
	} stats;

	/**
	 * Entry of the hit_list which stores the pre-DUT data
	 */
	struct entry {
		uint64_t timestamp;
		uint64_t identifier;
	};

	// initialize array and as many mutexes to ensure memory order
	struct entry hit_list[UINT24_MAX + 1] = {{0, 0}};
	std::mutex mtx[UINT24_MAX + 1];

	/**
	 * Add a pre DUT timestamp to the array.
	 *
	 * @param identification The identifier associated with this timestamp
	 * @param timestamp The timestamp
	 */
	static void add_entry(uint32_t identification, uint64_t timestamp) {
		uint32_t index = identification & INDEX_MASK;
		while (!mtx[index].try_lock());
		hit_list[index].timestamp = timestamp;
		hit_list[index].identifier = identification;
		mtx[index].unlock();
	}

	/**
	 * Check if there exists an entry in the array for the given identifier.
	 * Updates current mean and variance estimation..
	 *
	 * @param identification Identifier for which an entry is searched
	 * @param timestamp The post timestamp
	 */
	static void test_for(uint32_t identification, uint64_t timestamp) {
		uint32_t index = identification & INDEX_MASK;
		while (!mtx[index].try_lock());
		uint64_t old_ts = hit_list[index].identifier == identification ? hit_list[index].timestamp : 0;
		hit_list[index].timestamp = 0;
		hit_list[index].identifier = 0;
		mtx[index].unlock();
		if (old_ts != 0) {
			++stats.hits;
			// diff overflow improbable
			int64_t diff = timestamp - old_ts;
			if (diff < thresh) {
				std::cerr << "Measured latency below " << thresh
						  << " (Threshold). Ignoring...\n";
			}
			++count;
			double delta = diff - mean;
			mean = mean + delta / count;
			double delta2 = diff - mean;
			m2 = m2 + delta * delta2;
		} else {
			++stats.misses;
		}
	}

	/**
	 * Fetch statistics. Finalizes variance computation..
	 */
	static ms_stats fetch_stats() {
		if (count < 2) {
			std::cerr << "Not enough members to calculate mean and variance\n";
		} else {
			variance = m2 / (count - 1);
		}

		// Implicit cast from double to int64_t -> sub-nanosecond parts are discarded
		stats.average_latency = mean;
		stats.variance_latency = variance;
		return stats;
	}

	/**
	 * Log packets.
	 */
	void ms_log_pkts(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** rx_pkts, uint16_t nb_pkts, uint32_t seqnum_offset, const char* filename) {
		std::ofstream out (filename, std::ofstream::binary | std::ofstream::app);

		while (libmoon::is_running(0)) {
			uint16_t rx = rte_eth_rx_burst(port_id, queue_id, rx_pkts, nb_pkts);

			for (int i = 0; i < rx; i++) {
				if ((rx_pkts[i]->ol_flags | PKT_RX_IEEE1588_TMST) != 0) {
					uint32_t* timestamp32 = (uint32_t*)((uint8_t*)rx_pkts[i]->buf_addr + rx_pkts[i]->data_off + rx_pkts[i]->pkt_len - 8);
					uint32_t low = timestamp32[0];
					uint32_t high = timestamp32[1];
					uint64_t timestamp = high * 1000000000 + low;

					if (seqnum_offset < rx_pkts[i]->pkt_len) {
						uint32_t identifier = *(uint32_t*)((uint8_t*)rx_pkts[i]->buf_addr + rx_pkts[i]->data_off + seqnum_offset);

						out.write((char*)&timestamp, sizeof(timestamp));
						out.write((char*)&identifier, sizeof(identifier));
					} else {
						std::cerr << "Offset of sequence number greater than packet size\n";
					}
				}

				rte_pktmbuf_free(rx_pkts[i]);
			}
		}
	}
}

extern "C" {

void ms_set_thresh(int64_t thresh) {
	moonsniff::thresh = thresh;
}

void ms_add_entry(uint32_t identification, uint64_t timestamp) {
	moonsniff::add_entry(identification, timestamp);
}

void ms_test_for(uint32_t identification, uint64_t timestamp) {
	moonsniff::test_for(identification, timestamp);
}

moonsniff::ms_stats ms_fetch_stats() {
	return moonsniff::fetch_stats();
}

void ms_log_pkts(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** rx_pkts, uint16_t nb_pkts, uint32_t seqnum_offset, const char* filename) {
	moonsniff::ms_log_pkts(port_id, queue_id, rx_pkts, nb_pkts, seqnum_offset, filename);
}
}
