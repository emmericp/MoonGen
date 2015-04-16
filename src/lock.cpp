#include <cstdint>
#include <mutex>

extern "C" {
	
	using mutex = std::recursive_timed_mutex;

	mutex* make_lock() {
		return new mutex();
	}

	void lock_lock(mutex* lock) {
		lock->lock();
	}

	void lock_unlock(mutex* lock) {
		lock->unlock();
	}

	uint32_t lock_try_lock(mutex* lock) {
		return lock->try_lock();
	}

	uint32_t lock_try_lock_for(mutex* lock, uint32_t us) {
		return lock->try_lock_for(std::chrono::microseconds(us));
	}
}

