#include <stdint.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	uint8_t test_ctr = 0;

	static uint8_t getCtr(){
		return test_ctr;
	}

	static void incrementCtr(){
		++test_ctr;
	}
	
	// buffer holds the idetification values of packets
	// value 0 is reserved as unused/invalid
	uint16_t ring_buffer[BUFFER_SIZE] = {0};

	// next free entry in ring_buffer
	uint8_t head;

	// last entry which is currently part of the window
	uint8_t tail;

	// size of the active window
	uint8_t window;

	uint32_t hits = 0;
	uint32_t misses = 0;

	static uint32_t getHits(){ return hits; }
	static uint32_t getMisses(){ return misses; }

	static void init_buffer(uint8_t window_size){
		tail = 0;
		head = window_size;
	}

	static void advance_window(){
		++head;
		++tail;
	}

	static void add_entry(uint16_t identification){
		ring_buffer[head] = identification;
		advance_window();
	}

	static void test_for(uint16_t identification){
		if(tail < head){
			for(uint8_t i = tail; i < head; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;	
					return;
				}
			}
		}else if(head < tail){
			for(uint8_t i = tail; i < BUFFER_SIZE - 1; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;
					return;
				}
			}
			for(uint8_t i = 0; i < head; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;
					return;
				}
			}
		}
		// the identification is not part of the current window
		++misses;
	}
}

extern "C" {
	uint8_t ms_getCtr(){
		return moonsniff::getCtr();
	}

	void ms_incrementCtr(){
		moonsniff::incrementCtr();
	}

	void ms_init_buffer(uint8_t window_size){
		moonsniff::init_buffer(window_size);
	}
	
	void ms_add_entry(uint16_t identification){
		moonsniff::add_entry(identification);
	}

	void ms_test_for(uint16_t identification){
		moonsniff::test_for(identification);
	}

	uint32_t ms_get_hits(){ return moonsniff::getHits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }

}
