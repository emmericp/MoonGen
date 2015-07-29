#include <mutex>
#include <condition_variable>

struct barrier{
    std::mutex mutex;
    std::condition_variable cond;
    std::size_t n;
};

extern "C" {
    struct barrier* make_barrier(size_t n){
        struct barrier *b = new barrier;
        b->n = n;
        return b;
    }

    void barrier_wait(struct barrier *b){
        std::unique_lock<std::mutex> lock{b->mutex};
        if ( --b->n == 0 ){
            b->cond.notify_all();
        }else{
            b->cond.wait(lock, [ = ] { return b->n == 0;});
        }
    }

    void barrier_reinit(struct barrier *b, size_t n){
        std::unique_lock<std::mutex> lock{b->mutex};
        b->n = n;
    }
}
