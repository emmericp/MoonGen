#ifndef PIPE_HPP__
#define PIPE_HPP__

#include "spsc-queue/readerwriterqueue.h"

#ifdef __cplusplus
extern "C" {
#endif

void* try_dequeue(moodycamel::ReaderWriterQueue<void*>* queue);

#ifdef __cplusplus
}
#endif

#endif
