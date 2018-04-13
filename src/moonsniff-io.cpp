#include <cstdint>

#define MSCAP_SIZE 12

struct mscap {
	uint32_t identification;   /* identifies a received packet */
	uint64_t timestamp;  /* timestamp in nanoseconds */
};

extern "C" {
void libmoon_write_mscap(mscap *dst, uint32_t identification, uint64_t timestamp) {
	dst->identification = identification;
	dst->timestamp = timestamp;
}
}
