#include <stdint.h>

namespace moonsniff {
	uint8_t test_ctr = 0;

	static uint8_t getCtr(){
		return test_ctr;
	}

	static void incrementCtr(){
		++test_ctr;
	}
}

extern "C" {
	uint8_t ms_getCtr(){
		return moonsniff::getCtr();
	}

	void ms_incrementCtr(){
		moonsniff::incrementCtr();
	}
}
