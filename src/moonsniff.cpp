#include <stdint.h>
#include <deque>
#include <rte_rwlock.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	struct ms_entry {
		bool valid = false;
		uint64_t timestamp;
	};

	std::deque<uint64_t> latencies;
	
	ms_entry hit_list[UINT16_MAX];


	uint32_t hits = 0;
	uint32_t misses = 0;

	static uint32_t getHits(){ return hits; }
	static uint32_t getMisses(){ return misses; }


	static void add_entry(uint16_t identification, uint64_t timestamp){
		hit_list[identification].valid = true;
		hit_list[identification].timestamp = timestamp;
	}

	static void test_for(uint16_t identification, uint64_t timestamp){
		if( hit_list[identification].valid == true ){
			++hits;
			latencies.push_back(timestamp - hit_list[identification].timestamp);
			hit_list[identification].valid = false;
		} else {
			++misses;
		}
	}

	static uint64_t average_latency(){
		uint64_t size = 0;
		uint64_t sum = 0;
		for(auto it = latencies.cbegin(); it != latencies.cend(); ++it){
			sum += *it;
			++size;
		}
		return sum/size;
	}
}

extern "C" {
	void ms_add_entry(uint16_t identification, uint64_t timestamp){
		moonsniff::add_entry(identification, timestamp);
	}

	void ms_test_for(uint16_t identification, uint64_t timestamp){
		moonsniff::test_for(identification, timestamp);
	}

	uint64_t ms_average_latency(){
		return moonsniff::average_latency();
	}

	uint32_t ms_get_hits(){ return moonsniff::getHits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }

}
