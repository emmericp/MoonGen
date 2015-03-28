#include <cstdint>
#include <string>
#include <cstring>

#include "spsc-queue/readerwriterqueue.h"

using namespace moodycamel;

extern "C" {

	ReaderWriterQueue<void*>* make_pipe() {
		auto queue = new ReaderWriterQueue<void*>(512);
		return queue;
	}

	void enqueue(ReaderWriterQueue<void*>* queue, void* data) {
		queue->enqueue(data);
	}

	void* try_dequeue(ReaderWriterQueue<void*>* queue) {
		void* data;
		bool ok = queue->try_dequeue(data);
		return ok ? data : nullptr;
	}

	void* peek(ReaderWriterQueue<void*>* queue) {
		return queue->peek();
	}

	uint8_t pop(ReaderWriterQueue<void*>* queue) {
		return queue->pop();
	}

	size_t count(ReaderWriterQueue<void*>* queue) {
		return queue->size_approx();
	}
}

