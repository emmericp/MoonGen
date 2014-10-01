#include <stdbool.h>
#include <signal.h>
#include <time.h>

#include <rte_config.h>
#include <rte_cycles.h>

#include "lifecycle.h"

static volatile bool got_signal = false;
static volatile uint64_t stop_at = -1;

static void handler(int unused) {
	(void) unused;
	got_signal = true;
}

void install_signal_handlers() {
	signal(SIGINT, handler);
	signal(SIGTERM, handler);
}

uint8_t is_running() {
	return !got_signal && stop_at > rte_rdtsc();
}

void set_runtime(uint32_t run_time) {
	stop_at = rte_rdtsc() + run_time * rte_get_tsc_hz() / 1000;
}
