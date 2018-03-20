#include <stdint.h>
#include <deque>
#include <iostream>
#include <rte_rwlock.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	
	struct ms_entry {
		uint64_t timestamp;
		bool valid = false;
	};

	std::deque<uint64_t> latencies;
	
	ms_entry hit_list[UINT16_MAX];
	rte_rwlock_t mutex[UINT16_MAX];


	uint32_t hits = 0;
	uint32_t misses = 0;

	static uint32_t getHits(){ return hits; }
	static uint32_t getMisses(){ return misses; }
	
	static void init(){
		for(uint32_t i = 0; i < UINT16_MAX; ++i){
			rte_rwlock_init(&mutex[i]);
		}
	}

	static void add_entry(uint16_t identification, uint64_t timestamp){
		rte_rwlock_write_lock(&mutex[identification]);
		std::cout << "timestamp: " << timestamp << " for identification: " << identification << "\n";
		hit_list[identification].valid = true;
		hit_list[identification].timestamp = timestamp;
		//std::cout << "finished adding" << "\n";
		rte_rwlock_write_unlock(&mutex[identification]);
	}

	static void test_for(uint16_t identification, uint64_t timestamp){
		rte_rwlock_write_lock(&mutex[identification]);
		if( hit_list[identification].valid == true ){
			++hits;
			latencies.push_back(timestamp - hit_list[identification].timestamp);
			std::cout << "new: " << timestamp << "\n";
			std::cout << "old: " << hit_list[identification].timestamp << "\n";
			std::cout << "difference: " << (timestamp - hit_list[identification].timestamp)/1e6 << " ms\n";
			hit_list[identification].valid = false;
		} else {
			++misses;
		}
		rte_rwlock_write_unlock(&mutex[identification]);
	}

	static uint64_t average_latency(){
		uint64_t size = 0;
		uint64_t sum = 0;
		for(auto it = latencies.cbegin(); it != latencies.cend(); ++it){
			sum += *it;
			++size;
		}
		std::cout << "sum: " << sum << ", length: " << latencies.size() << ", size: " << size << "\n";
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
	
	void ms_init(){ moonsniff::init(); }
	uint32_t ms_get_hits(){ return moonsniff::getHits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }

}
