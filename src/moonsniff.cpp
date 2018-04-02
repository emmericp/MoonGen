#include <stdint.h>
#include <deque>
#include <iostream>
#include <fstream>
#include <rte_rwlock.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	
	struct ms_entry {
		uint64_t timestamp;
		bool valid = false;
	};

	struct ms_stats {
		uint64_t average_latency = 0;
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t inval_ts = 0;
	};

	ms_stats stats;

	std::deque<uint64_t> latencies;
	std::ofstream file;
	
	ms_entry hit_list[UINT16_MAX];
	rte_rwlock_t mutex[UINT16_MAX];


	uint32_t hits = 0;
	uint32_t misses = 0;
	uint32_t inval_ts = 0; // computed latency is invalid, e.g. negative

	static uint32_t getHits(){ return hits; }
	static uint32_t getMisses(){ return misses; }
	static uint32_t getInvalidTS(){ return inval_ts; }
	
	static void init(){
		for(uint32_t i = 0; i < UINT16_MAX; ++i){
			rte_rwlock_init(&mutex[i]);
		}
		file.open("latencies.csv");
	}

	static void finish(){
		file.close();
	}

	static void add_entry(uint16_t identification, uint64_t timestamp){
		rte_rwlock_write_lock(&mutex[identification]);
		//std::cout << "timestamp: " << timestamp << " for identification: " << identification << "\n";
		hit_list[identification].valid = true;
		hit_list[identification].timestamp = timestamp;
		//std::cout << "finished adding" << "\n";
		rte_rwlock_write_unlock(&mutex[identification]);
	}

	static void test_for(uint16_t identification, uint64_t timestamp){
		rte_rwlock_write_lock(&mutex[identification]);
		if( hit_list[identification].valid == true ){
			++stats.hits;
			file << hit_list[identification].timestamp << " " << timestamp << "\n";

			//std::cout << "new: " << timestamp << "\n";
			//std::cout << "old: " << hit_list[identification].timestamp << "\n";
			//std::cout << "difference: " << (timestamp - hit_list[identification].timestamp)/1e6 << " ms\n";
			hit_list[identification].valid = false;
		} else {
			++stats.misses;
		}
		rte_rwlock_write_unlock(&mutex[identification]);
	}

	static ms_stats post_process(const char* fileName){
		std::ifstream file(fileName);
		uint64_t pre, post;
		uint64_t size = 0, sum = 0;

		while( file >> pre >> post ){
			if( pre < post && post - pre < 1e9 ){
				sum += post - pre;
				++size;
			} else {
				++stats.inval_ts;
			}
		}
		std::cout << size << ", " << sum << "\n";
		stats.average_latency = size != 0 ? sum/size : 0;
		return stats;
	}
}

extern "C" {
	void ms_add_entry(uint16_t identification, uint64_t timestamp){
		moonsniff::add_entry(identification, timestamp);
	}

	void ms_test_for(uint16_t identification, uint64_t timestamp){
		moonsniff::test_for(identification, timestamp);
	}

	moonsniff::ms_stats ms_post_process(const char* fileName){
		return moonsniff::post_process(fileName);
	}
	
	void ms_init(){ moonsniff::init(); }
	void ms_finish(){ moonsniff::finish(); }
	uint32_t ms_get_hits(){ return moonsniff::getHits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }
	uint32_t ms_get_invalid_timestamps(){ return moonsniff::getInvalidTS();}

}
