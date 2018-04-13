#include <cstdint>

struct mscap {
	uint64_t timestamp;  /* timestamp in nanoseconds */
	uint32_t identification;   /* identifies a received packet */
	// padding of 4 bytes
};

extern "C" {
void libmoon_write_mscap(mscap *dst, uint32_t identification, uint64_t timestamp) {
	dst->identification = identification;
	dst->timestamp = timestamp;
}
}
