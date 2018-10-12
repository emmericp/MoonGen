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
#include <atomic>
#include <iostream>
#include <unistd.h>
#include "ring.h"
#include "lifecycle.hpp"

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

	struct limiter_control {
		std::atomic<uint64_t> count = {0};
		std::atomic<uint64_t> stop = {0};

		inline bool running() {
			return libmoon::is_running(0) && !stop.load(std::memory_order_relaxed);
		};

		inline void count_packets(uint64_t n) {
			count.fetch_add(n, std::memory_order_relaxed);
		};
	};
	static_assert(sizeof(limiter_control) == 16, "struct size mismatch");
	
	/*
	 * Arbitrary time software rate control main
	 * link_speed: DPDK link speed is expressed in Mbit/s
	 */
	static inline void main_loop(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t link_speed, limiter_control* ctl) {
		uint64_t tsc_hz = rte_get_tsc_hz();
		uint64_t id_cycles = 0;
		struct rte_mbuf* bufs[batch_size];
		double link_bps = link_speed * 1000000.0;
		uint64_t cur = rte_get_tsc_cycles();
		uint64_t next_send = cur;
		while (libmoon::is_running(0)) {
			int cur_batch_size = batch_size;
			int n = ring_dequeue(ring, reinterpret_cast<void**>(bufs), cur_batch_size);
			while (!n && cur_batch_size > 1) {
				cur_batch_size /= 2;
				n = ring_dequeue(ring, reinterpret_cast<void**>(bufs), cur_batch_size);
			}
			if (n) {
				for (int i = 0; i < cur_batch_size; i++) {
					// desired inter-frame spacing is encoded in the udata field (bytes on the wire)
					id_cycles = ((uint64_t) bufs[i]->udata64 * 8 / link_bps) * tsc_hz;
					next_send += id_cycles;
					while ((cur = rte_get_tsc_cycles()) < next_send);
					while (rte_eth_tx_burst(device, queue, bufs + i, 1) == 0) {
						if (!ctl->running()) {
							return;
						}
					}
				}
				ctl->count_packets(n);
			} else if (!ctl->running()) {
				return;
			}
		}
		return;
	}
	
	static inline void main_loop_poisson(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed, limiter_control* ctl) {
		uint64_t tsc_hz = rte_get_tsc_hz();
		// control IPGs instead of IDT as IDTs < packet_time are physically impossible
		std::default_random_engine rand;
		uint64_t next_send = 0;
		struct rte_mbuf* bufs[batch_size];
		while (libmoon::is_running(0)) {
			int n = ring_dequeue(ring, reinterpret_cast<void**>(bufs), batch_size);
			uint64_t cur = rte_get_tsc_cycles();
			// nothing sent for 10 ms, restart rate control
			if (((int64_t) cur - (int64_t) next_send) > (int64_t) tsc_hz / 100) {
				next_send = cur;
			}
			if (n) {
				for (int i = 0; i < n; i++) {
					uint64_t pkt_time = (bufs[i]->pkt_len + 24) * 8 / (link_speed / 1000);
					// ns to cycles
					pkt_time *= (double) tsc_hz / 1000000000.0;
					int64_t avg = (int64_t) (tsc_hz / (1000000000.0 / target) - pkt_time);
					while ((cur = rte_get_tsc_cycles()) < next_send);
					std::exponential_distribution<double> distribution(1.0 / avg);
					double delay = (avg <= 0) ? 0 : distribution(rand);
					next_send += pkt_time + delay;
					while (rte_eth_tx_burst(device, queue, bufs + i, 1) == 0) {
						if (!ctl->running()) {
							return;
						}
					}
				}
				ctl->count_packets(n);
			} else if (!ctl->running()) {
				return;
			}
		}
	}

	static inline void main_loop_cbr(struct rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, limiter_control* ctl) {
		uint64_t tsc_hz = rte_get_tsc_hz();
		uint64_t id_cycles = (uint64_t) (target / (1000000000.0 / ((double) tsc_hz)));
		uint64_t next_send = 0;
		struct rte_mbuf* bufs[batch_size];
		while (libmoon::is_running(0)) {
			int n = ring_dequeue(ring, reinterpret_cast<void**>(bufs), batch_size);
			uint64_t cur = rte_get_tsc_cycles();
			// nothing sent for 10 ms, restart rate control
			if (((int64_t) cur - (int64_t) next_send) > (int64_t) tsc_hz / 100) {
				next_send = cur;
			}
			if (n) {
				for (int i = 0; i < n; i++) {
					while ((cur = rte_get_tsc_cycles()) < next_send);
					next_send += id_cycles;
					while (rte_eth_tx_burst(device, queue, bufs + i, 1) == 0) {
						// mellanox nics like to not accept packets when stopping for... reasons
						if (!ctl->running()) {
							return;
						}
					}
				}
				ctl->count_packets(n);
			} else if (!ctl->running()) {
				return;
			}
		}
	}
}

extern "C" {
	void mg_rate_limiter_cbr_main_loop(rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, rate_limiter::limiter_control* ctl) {
		rate_limiter::main_loop_cbr(ring, device, queue, target, ctl);
	}

	void mg_rate_limiter_poisson_main_loop(rte_ring* ring, uint8_t device, uint16_t queue, uint32_t target, uint32_t link_speed, rate_limiter::limiter_control* ctl) {
		rate_limiter::main_loop_poisson(ring, device, queue, target, link_speed, ctl);
	}

	void mg_rate_limiter_main_loop(rte_ring* ring, uint8_t device, uint16_t queue, uint32_t link_speed, rate_limiter::limiter_control* ctl) {
		rate_limiter::main_loop(ring, device, queue, link_speed, ctl);
	}
}

