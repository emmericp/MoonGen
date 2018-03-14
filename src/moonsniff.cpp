#include <stdint.h>
#include <rte_rwlock.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	struct ms_entry {
		bool valid = false;
		uint64_t timestamp;
	};

	
	ms_entry hit_list[UINT16_MAX];


	uint32_t hits = 0;
	uint32_t misses = 0;

	static uint32_t getHits(){ return hits; }
	static uint32_t getMisses(){ return misses; }


	static void add_entry(uint16_t identification){
		hit_list[identification].valid = true;
	}

	static void test_for(uint16_t identification){
		if( hit_list[identification].valid == true ){
			++hits;
			hit_list[identification].valid = false;
		} else {
			++misses;
		}
	}
}

extern "C" {
	void ms_add_entry(uint16_t identification){
		moonsniff::add_entry(identification);
	}

	void ms_test_for(uint16_t identification){
		moonsniff::test_for(identification);
	}

	uint32_t ms_get_hits(){ return moonsniff::getHits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }

}
