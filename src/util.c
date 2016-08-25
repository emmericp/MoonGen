#include <stdint.h>
#include <rte_config.h>
#include <rte_ip.h>
#include <rte_udp.h>
#include <rte_byteorder.h>
#include <rte_mbuf.h>
#include <rte_memcpy.h>
#include <rte_lcore.h>

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

void print_ptr(void* ptr) {
	printf("ptr = %p\n", ptr);
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
// offset: udp - 20; tcp - 25
void calc_ipv4_pseudo_header_checksum(void* data, int offset) {
	uint16_t csum = get_ipv4_psd_sum((struct ipv4_hdr*) ((uint8_t*)data + 14));
	((uint16_t*) data)[offset] = csum;
}

void calc_ipv4_pseudo_header_checksums(struct rte_mbuf** data, int n, int offset) {
	for (int i = 0; i < n; i++) {
		calc_ipv4_pseudo_header_checksum(rte_pktmbuf_mtod(data[i], void*), offset);
	}
}

static inline uint16_t get_16b_sum(uint16_t *ptr16, uint32_t nr)
{
	uint32_t sum = 0;
	while (nr > 1)
	{
		sum +=*ptr16;
		nr -= sizeof(uint16_t);
		ptr16++;
		if (sum > UINT16_MAX)
			sum -= UINT16_MAX;
	}

	/* If length is in odd bytes */
	if (nr)
		sum += *((uint8_t*)ptr16);

	sum = ((sum & 0xffff0000) >> 16) + (sum & 0xffff);
	sum &= 0x0ffff;
	return (uint16_t)sum;
}

static inline uint16_t get_ipv6_psd_sum (struct ipv6_hdr * ip_hdr)
{
	/* Pseudo Header for IPv6/UDP/TCP checksum */
	union ipv6_psd_header {
		struct {
			uint8_t src_addr[16]; /* IP address of source hosts */
			uint8_t dst_addr[16]; /* IP address of destination host(s) */
			uint32_t len;         /* L4 length. */
			uint32_t proto;       /* L4 protocol - top 3 bytes must be zero */
		} __attribute__((__packed__));
		
		uint16_t u16_arr[0]; /* allow use as 16-bit values with safe aliasing */
	} psd_hdr;

	rte_memcpy(&psd_hdr.src_addr, ip_hdr->src_addr, 
			sizeof(ip_hdr->src_addr) + sizeof(ip_hdr->dst_addr));
	psd_hdr.len       = ip_hdr->payload_len;
	psd_hdr.proto     = (ip_hdr->proto << 24);
	
	return get_16b_sum(psd_hdr.u16_arr, sizeof(psd_hdr));                   
}

// TODO: cope with flexible offsets and different protocols
// offset: udp - 30; tcp - 35
void calc_ipv6_pseudo_header_checksum(void* data, int offset) {
	uint16_t csum = get_ipv6_psd_sum((struct ipv6_hdr*) ((uint8_t*)data + 14));
	((uint16_t*) data)[offset] = csum;
}

void calc_ipv6_pseudo_header_checksums(struct rte_mbuf** data, int n, int offset) {
	for (int i = 0; i < n; i++) {
		calc_ipv6_pseudo_header_checksum(rte_pktmbuf_mtod(data[i], void*), offset);
	}
}


// rte_lcore/socket_id are static in rte_lcore.h
uint32_t get_current_core() {
	return rte_lcore_id();
}

uint32_t get_current_socket() {
	return rte_socket_id();
}

