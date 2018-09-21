#include <cstdint>
#include <string>
#include <iostream>
#include <mutex>

#define UINT24_MAX 16777215
#define INDEX_MASK (uint32_t) 0x00FFFFFF
#define NEGATIVE_THRESH -100 // Latencies smaller than this threshold are ignored


/*
 * This namespace holds functions which are used by MoonSniff's Live Mode
 *
 * Other modes are implemented in examples/moonsniff/
 */
namespace moonsniff {

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

	// initialize array and as many mutexes to ensure memory order
	uint64_t hit_list[UINT24_MAX + 1] = { 0 };
	std::mutex mtx[UINT24_MAX + 1];

	/**
	 * Add a pre DUT timestamp to the array.
	 *
	 * @param identification The identifier associated with this timestamp
	 * @param timestamp The timestamp
	 */
	static void add_entry(uint32_t identification, uint64_t timestamp){
		uint32_t index = identification & INDEX_MASK;
		while(!mtx[index].try_lock());
		hit_list[index] = timestamp;
		mtx[index].unlock();
	}

	/**
	 * Check if there exists an entry in the array for the given identifier.
	 * Updates current mean and variance estimation..
	 *
	 * @param identification Identifier for which an entry is searched
	 * @param timestamp The post timestamp
	 */
	static void test_for(uint32_t identification, uint64_t timestamp){
		uint32_t index = identification & INDEX_MASK;
		while(!mtx[index].try_lock());
		uint64_t old_ts = hit_list[index];
		hit_list[index] = 0;
		mtx[index].unlock();
		if( old_ts != 0 ){
			++stats.hits;
			// diff overflow improbable (latency > 290 years)
			int64_t diff = timestamp - old_ts;
			if (diff < -NEGATIVE_THRESH){
				std::cerr << "Measured latency below " << NEGATIVE_THRESH
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
	static ms_stats fetch_stats(){
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
}

extern "C" {
	void ms_add_entry(uint32_t identification, uint64_t timestamp){
		moonsniff::add_entry(identification, timestamp);
	}

	void ms_test_for(uint32_t identification, uint64_t timestamp){
		moonsniff::test_for(identification, timestamp);
	}

	moonsniff::ms_stats ms_fetch_stats(){
		return moonsniff::fetch_stats();
	}
}
