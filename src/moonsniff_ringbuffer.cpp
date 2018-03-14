#include <stdint.h>
#include <rte_rwlock.h>

#define BUFFER_SIZE 256

namespace moonsniff {
	uint8_t test_ctr = 0;

	static uint8_t getCtr(){
		return test_ctr;
	}

	static void incrementCtr(){
		++test_ctr;
	}

	rte_rwlock_t mutex;
	
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
	uint32_t forwardhits = 0;
	uint32_t misses = 0;
	uint32_t wrap_misses = 0;

	static uint32_t getHits(){ return hits; }
	static uint32_t getForwardhits(){ return forwardhits; }
	static uint32_t getMisses(){ return misses; }
	static uint32_t getWrapMisses(){ return wrap_misses; }

	static void init_buffer(uint8_t window_size){
		tail = 0;
		head = window_size;
		rte_rwlock_init(&mutex);
	}

	static void advance_window(){
		++head;
		++tail;
	}

	static void add_entry(uint16_t identification){
		rte_rwlock_write_lock(&mutex);
		ring_buffer[head] = identification;
		advance_window();
		rte_rwlock_write_unlock(&mutex);
	}

	static void test_for(uint16_t identification){
		rte_rwlock_read_lock(&mutex);
		uint8_t _tail = tail;
		uint8_t _head = head;
		//rte_rwlock_read_unlock(&mutex);

		if(_tail < _head){
			// running variable must allow for higher values as uint8_t
			// otherwise wrap around could cause the condition to always hold
			for(uint16_t i = _tail; i < _head; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;	
					++forwardhits;
					rte_rwlock_read_unlock(&mutex);
					return;
				}
			}
		}else if(_head < _tail){
			for(uint16_t i = _tail; i < BUFFER_SIZE; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;
					rte_rwlock_read_unlock(&mutex);
					return;
				}
			}
			for(uint16_t i = 0; i < _head; ++i){
				if(ring_buffer[i] == identification){
					ring_buffer[i] = 0;
					++hits;
					rte_rwlock_read_unlock(&mutex);
					return;
				}
			}
			++wrap_misses;
		}
		// the identification is not part of the current window
		++misses;
		rte_rwlock_read_unlock(&mutex);
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
	uint32_t ms_get_forward_hits(){ return moonsniff::getForwardhits(); }
	uint32_t ms_get_misses(){ return moonsniff::getMisses(); }
	uint32_t ms_get_wrap_misses(){ return moonsniff::getWrapMisses(); }

}
