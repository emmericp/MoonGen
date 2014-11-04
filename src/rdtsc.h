#ifndef RDTSC_H__
#define RDTSC_H__

#include <stdint.h>

union tsc_t {
	uint64_t tsc_64;
	struct {
		uint32_t lo_32;
		uint32_t hi_32;
	};
};

/**
 * Read value of TSC register without enforced serialization.
 * Taken from "How to Benchmark Code Execution Times on Intel IA-32 and IA-64 Instruction Set Architectures"
 *
 * @return
 *   Value of TSC register
 */
inline static uint64_t read_rdtsc() {
	union tsc_t tsc;
	asm volatile("RDTSC\n\t" 
	             "mov %%edx, %0\n\t" 
	             "mov %%eax, %1\n\t" 
	             : "=r" (tsc.hi_32), 
	             "=r" (tsc.lo_32):: "%rax", "%rbx", "%rcx", "%rdx");
	return tsc.tsc_64;
}

/**
 * Read value of TSC register with enforced serialization.
 * Taken from "How to Benchmark Code Execution Times on Intel IA-32 and IA-64 Instruction Set Architectures"
 *
 * @return
 *   Value of TSC register
 */
inline uint64_t read_rdtscp(void) {
	union tsc_t tsc;
	asm volatile("RDTSCP\n\t" 
	             "mov %%edx, %0\n\t" 
	             "mov %%eax, %1\n\t" 
	             : "=r" (tsc.hi_32), 
	             "=r" (tsc.lo_32):: "%rax", "%rbx", "%rcx", "%rdx");
	return tsc.tsc_64;
}

#endif
