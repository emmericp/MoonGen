#include <stdint.h>
#include <rte_config.h>
#include <rte_ip.h>
#include <rte_udp.h>
#include <rte_byteorder.h>
#include <rte_mbuf.h>

// copied from rte_cycles.h (defined as static inline there)
uint64_t rte_rdtsc() {
	union {
		uint64_t tsc_64;
		struct {
			uint32_t lo_32;
			uint32_t hi_32;
		};
	} tsc;
	asm volatile("rdtsc" :
		     "=a" (tsc.lo_32),
		     "=d" (tsc.hi_32));
	return tsc.tsc_64;
}


static inline uint16_t get_ipv4_psd_sum (struct ipv4_hdr* ip_hdr) {
	uint16_t len = ip_hdr->total_length;
	// TODO: depends on CPU endianess
	// and yes, this optimization is actually worth it:
	//	* 400% increase in micro-benchmarks
	//	* 1.2% in l3-multi-flows.lua 
	if (len & 0xFF) { // lower (network byte order) byte used --> len >= 256
		// just use swap
		len = rte_bswap16((uint16_t)(rte_bswap16(len) - sizeof(struct ipv4_hdr)));
	} else {
		// can use shift instead, yeah.
		len = ((len >> 8) - sizeof(struct ipv4_hdr)) << 8;
	}
	uint64_t sum = (uint64_t) ip_hdr->src_addr + (uint64_t) ip_hdr->dst_addr + (uint64_t) ((ip_hdr->next_proto_id << 24) | len);
	uint32_t lower = sum & 0xFFFFFFFF;
	uint32_t upper = sum >> 32;
	lower += upper;
	if (lower < upper) lower++;
	uint16_t lower16 = lower & 0xFFFF;
	uint16_t upper16 = lower >> 16;
	lower16 += upper16;
	if (lower16 < upper16) lower16++;
	return lower16;
}

// TODO: cope with flexible offsets
void calc_ipv4_pseudo_header_checksum(void* data) {
	uint16_t csum = get_ipv4_psd_sum((struct ipv4_hdr*) ((uint8_t*)data + 14));
	((uint16_t*) data)[20] = csum;
}

void calc_ipv4_pseudo_header_checksums(struct rte_mbuf** data, int n) {
	for (int i = 0; i < n; i++) {
		calc_ipv4_pseudo_header_checksum(data[i]->pkt.data);
	}
}

