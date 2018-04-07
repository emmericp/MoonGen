#include <stdint.h>
#include <deque>
#include <iostream>
#include <fstream>
#include <mutex>
#include <thread>

#define UINT24_MAX 16777215

namespace moonsniff {
	
	struct ms_stats {
		uint64_t average_latency = 0;
		uint32_t hits = 0;
		uint32_t misses = 0;
		uint32_t inval_ts = 0;
	};

	ms_stats stats;

	std::ofstream file;
	
	uint64_t hit_list[UINT24_MAX + 1] = { 0 };

	static void init(const char* fileName){
		file.open(fileName);
	}

	static void finish(){
		file.close();
	}

	static void add_entry(uint32_t identification, uint64_t timestamp){
		//std::cout << "timestamp: " << timestamp << " for identification: " << identification << "\n";
		hit_list[identification & 0x00ffffff] = timestamp;
		//std::cout << "finished adding" << "\n";
	}

	static void test_for(uint32_t identification, uint64_t timestamp){
		uint64_t old_ts = hit_list[identification & 0x00ffffff];
		hit_list[identification & 0x00ffffff] = 0;
		if( old_ts != 0 ){
			++stats.hits;
			file << old_ts << " " << timestamp << "\n";

			//std::cout << "new: " << timestamp << "\n";
			//std::cout << "old: " << hit_list[identification].timestamp << "\n";
			//std::cout << "difference: " << (timestamp - hit_list[identification].timestamp)/1e6 << " ms\n";
		} else {
			++stats.misses;
		}
	}

	static ms_stats post_process(const char* fileName){
		std::ifstream ifile;
		ifile.open(fileName);
		uint64_t pre, post;
		uint64_t size = 0, sum = 0;

		while( ifile >> pre >> post ){
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
	void ms_add_entry(uint32_t identification, uint64_t timestamp){
		moonsniff::add_entry(identification, timestamp);
	}

	void ms_test_for(uint32_t identification, uint64_t timestamp){
		moonsniff::test_for(identification, timestamp);
	}

	moonsniff::ms_stats ms_post_process(const char* fileName){
		return moonsniff::post_process(fileName);
	}
	
	void ms_init(const char* fileName){ moonsniff::init(fileName); }
	void ms_finish(){ moonsniff::finish(); }

}
