#include <rte_config.h>
#include <rte_common.h>
#include <rte_ring.h>
#include <rte_mbuf.h>
#include <stdint.h>
#include <rte_ethdev.h> 
#include <rte_mempool.h>
#include <rte_ether.h>
#include <rte_cycles.h>
#include <random>
#include <iostream>
#include "ring.h"

// required for gcc 4.7 for some reason
// ???
#ifndef UINT8_MAX
#define UINT8_MAX 255
#endif
#ifndef UINT16_MAX
#define UINT16_MAX 65535U
#endif

// FIXME: duplicate code (needed for a paper, so the usual quick & dirty hacks)
namespace rate_limiter {
	constexpr int batch_size = 64;
	
	// FIXME: actually do the right thing
	static inline void main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue) {
		struct rte_mbuf* bufs[batch_size];
		while (1) {
			int rc = ring_dequeue(ring, reinterpret_cast<void**>(bufs), batch_size);
			if (rc == 0) {
				uint32_t sent = 0;
				while (sent < batch_size) {
					sent += rte_eth_tx_burst(device, queue, bufs + sent, batch_size - sent);
				}
			}
		}
	}

	
	// FIXME: support packet sizes here
	static inline void main_loop_poisson(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed) {
		uint64_t tsc_hz = rte_get_tsc_hz();
		// control IPGs instead of IDT as IDTs < packet_time are physically impossible
		std::default_random_engine rand;
		uint64_t next_send = 0;
		struct rte_mbuf* bufs[batch_size];
		while (1) {
			int rc = ring_dequeue(ring, reinterpret_cast<void**>(bufs), batch_size);
			uint64_t cur = rte_get_tsc_cycles();
			// nothing sent for 10 ms, restart rate control
			if (((int64_t) cur - (int64_t) next_send) > (int64_t) tsc_hz / 100) {
				next_send = cur;
			}
			if (rc == 0) {
				uint32_t sent = 0;
				while (sent < batch_size) {
					uint64_t pkt_time = (bufs[sent]->pkt_len + 24) * 8 / (link_speed / 1000);
					uint64_t avg = (uint64_t) (tsc_hz / (1000000000 / target) - pkt_time);
					std::exponential_distribution<double> distribution(1.0 / avg);
					while ((cur = rte_get_tsc_cycles()) < next_send);
					next_send += distribution(rand) + pkt_time;
					sent += rte_eth_tx_burst(device, queue, bufs + sent, 1);
				}
			}
		}
	}

	static inline void main_loop_cbr(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target) {
		uint64_t tsc_hz = rte_get_tsc_hz();
		uint64_t id_cycles = (uint64_t) (target / (1000000000.0 / ((double) tsc_hz)));
		uint64_t next_send = 0;
		struct rte_mbuf* bufs[batch_size];
		while (1) {
			int rc = ring_dequeue(ring, reinterpret_cast<void**>(bufs), batch_size);
			uint64_t cur = rte_get_tsc_cycles();
			// nothing sent for 10 ms, restart rate control
			if (((int64_t) cur - (int64_t) next_send) > (int64_t) tsc_hz / 100) {
				next_send = cur;
			}
			if (rc == 0) {
				uint32_t sent = 0;
				while (sent < batch_size) {
					while ((cur = rte_get_tsc_cycles()) < next_send);
					next_send += id_cycles;
					sent += rte_eth_tx_burst(device, queue, bufs + sent, 1);
				}
			}
		}
	}
}

extern "C" {
	void rate_limiter_cbr_main_loop(rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target) {
		rate_limiter::main_loop_cbr(ring, device, queue, target);
	}

	void rate_limiter_poisson_main_loop(rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed) {
		rate_limiter::main_loop_poisson(ring, device, queue, target, link_speed);
	}

	void rate_limiter_main_loop(rte_ring* ring, uint8_t device, uint16_t queue) {
		rate_limiter::main_loop(ring, device, queue);
	}
}

