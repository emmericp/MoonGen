#include <stdint.h>
#include <stdlib.h>
#include <rte_config.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include <rte_mempool.h>
#include <stdio.h>

#include "device.h"

static uint64_t bad_pkts_sent[RTE_MAX_ETHPORTS];
static uint64_t bad_bytes_sent[RTE_MAX_ETHPORTS];

uint64_t moongen_get_bad_pkts_sent(uint8_t port_id) {
	return __sync_fetch_and_add(&bad_pkts_sent[port_id], 0);
}

uint64_t moongen_get_bad_bytes_sent(uint8_t port_id) {
	return __sync_fetch_and_add(&bad_bytes_sent[port_id], 0);
}

static struct rte_mbuf* get_delay_pkt_bad_crc(struct rte_mempool* pool, uint32_t* rem_delay, uint32_t min_pkt_size) {
	// _Thread_local support seems to suck in (older?) gcc versions?
	// this should give us the best compatibility
	static __thread uint32_t target = 0;
	static __thread uint32_t current = 0;
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
	if (delay < min_pkt_size) {
		*rem_delay = min_pkt_size; // will be set to 0 at the end of the function
		delay = min_pkt_size;
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
	pkt->data_len = delay - 20;
	pkt->pkt_len = delay - 20;
	pkt->ol_flags |= PKT_TX_NO_CRC_CSUM;
	current += delay;
	return pkt;
}


void moongen_send_all_packets_with_delay_bad_crc(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct rte_mempool* pool, uint32_t min_pkt_size) {
	const int BUF_SIZE = 128;
	struct rte_mbuf* pkts[BUF_SIZE];
	int send_buf_idx = 0;
	uint32_t num_bad_pkts = 0;
	uint32_t num_bad_bytes = 0;
	for (uint16_t i = 0; i < num_pkts; i++) {
		struct rte_mbuf* pkt = load_pkts[i];
		// desired inter-frame spacing is encoded in the hash 'usr' field
		uint32_t delay = (uint32_t) pkt->udata64;
		// step 1: generate delay-packets
		while (delay > 0) {
			struct rte_mbuf* pkt = get_delay_pkt_bad_crc(pool, &delay, min_pkt_size);
			if (pkt) {
				num_bad_pkts++;
				// packet size: [MAC, CRC] to be consistent with HW counters
				num_bad_bytes += pkt->pkt_len;
				pkts[send_buf_idx++] = pkt;
			}
			if (send_buf_idx >= BUF_SIZE) {
				dpdk_send_all_packets(port_id, queue_id, pkts, send_buf_idx);
				send_buf_idx = 0;
			}
		}
		// step 2: send the packet
		pkts[send_buf_idx++] = pkt;
		if (send_buf_idx >= BUF_SIZE || i + 1 == num_pkts) { // don't forget to send the last batch
			dpdk_send_all_packets(port_id, queue_id, pkts, send_buf_idx);
			send_buf_idx = 0;
		}
	}
	// atomic as multiple threads may use the same stats register from multiple queues
	__sync_fetch_and_add(&bad_pkts_sent[port_id], num_bad_pkts);
	__sync_fetch_and_add(&bad_bytes_sent[port_id], num_bad_bytes);
	return;
}

void moongen_send_all_packets_with_delay_bad_crc_loss(uint8_t port_id, uint16_t queue_id, struct rte_mbuf** load_pkts, uint16_t num_pkts, struct rte_mempool* pool, uint32_t min_pkt_size, double loss_rate) {
	const int BUF_SIZE = 128;
	struct rte_mbuf* pkts[BUF_SIZE];
	int send_buf_idx = 0;
	uint32_t num_bad_pkts = 0;
	uint32_t num_bad_bytes = 0;
	printf("moongen_send_all_packets_with_delay_bad_crc_loss(%d)...\n",num_pkts);
	if (num_pkts>0) {
		printf("\tudata64=%lx\t%p\n",load_pkts[0]->udata64,load_pkts[0]);
		printf("\ttimesync=%04x\tseqn=%08x\tpacket_type=%08x\tuserdata=%p\tpool=%p\tnext=%p\ttx_offload=%lx\n",
				load_pkts[0]->timesync,load_pkts[0]->seqn,load_pkts[0]->packet_type,load_pkts[0]->userdata,load_pkts[0]->pool,load_pkts[0]->next,load_pkts[0]->tx_offload);
		if (load_pkts[0]->udata64 > 0x0fffffff) {
			printf("WARNINGWARNING\n");
			//printf("\tudata points to: %08x\n",*((uint32_t*)(load_pkts[0]->userdata)));
		}
	}
	for (uint16_t i = 0; i < num_pkts; i++) {
		struct rte_mbuf* pkt;
		printf("\tinside forloop udata64=%lx\t%p\n",load_pkts[0]->udata64,load_pkts[0]);
		pkt = load_pkts[i];
		// desired inter-frame spacing is encoded in the hash 'usr' field
		uint32_t delay = (uint32_t) pkt->udata64;
		// step 1: generate delay-packets
		printf("\tentering whileloop delay is %08x\t%lx\n",delay,pkt->udata64);
		while (delay > 0) {
			printf("\tcalling get_delay_pkt_bad_crc(%08x)\n",delay);
			struct rte_mbuf* bad_pkt = get_delay_pkt_bad_crc(pool, &delay, min_pkt_size);
			printf("\treturned delay = %08x\n",delay);
			if (bad_pkt) {
				num_bad_pkts++;
				// packet size: [MAC, CRC] to be consistent with HW counters
				num_bad_bytes += bad_pkt->pkt_len;
				pkts[send_buf_idx++] = bad_pkt;
			}
			if (send_buf_idx >= BUF_SIZE) {
				printf("111 dpdk_send_all_packets(%d, %08x, %d, %d)\n",send_buf_idx, delay, i, num_pkts);
				dpdk_send_all_packets(port_id, queue_id, pkts, send_buf_idx);
				printf("done\n");
				send_buf_idx = 0;
			}
		}
		// step 2: send the packet
		// include random losses
		if ((double)rand()/RAND_MAX >= loss_rate) {
			pkts[send_buf_idx++] = pkt;
		}
		if (send_buf_idx >= BUF_SIZE || i + 1 == num_pkts) { // don't forget to send the last batch
			printf("222 dpdk_send_all_packets(%d, %08x, %d, %d)\n",send_buf_idx, delay, i, num_pkts);
			dpdk_send_all_packets(port_id, queue_id, pkts, send_buf_idx);
			printf("done\n");
			send_buf_idx = 0;
		}
	}
	//printf("done1\n");
	// atomic as multiple threads may use the same stats register from multiple queues
	__sync_fetch_and_add(&bad_pkts_sent[port_id], num_bad_pkts);
	__sync_fetch_and_add(&bad_bytes_sent[port_id], num_bad_bytes);
	//printf("done2\n");
	return;
}

