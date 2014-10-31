#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include <lauxlib.h>
#include <lualib.h>

#include "task.h"
#include "lifecycle.h"

#include <rte_config.h>

#ifndef RTE_LIBRTE_IEEE1588
#error "IEEE1588 support disabled in dpdk"
#endif

void print_usage() {
	printf("Usage: MoonGen [--dpdk-config=<config>] <script> [script args...]\n");
}

int main(int argc, char **argv) {
	if (argc < 2) {
		print_usage();
		return 1;
	}
	install_signal_handlers();
	lua_State* L = launch_lua();
	if (!L) {
		return -1;
	}
	lua_getglobal(L, "main");
	lua_pushstring(L, "master");
	for (int i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
	}
	if (lua_pcall(L, argc + 1, 0, 0)) {
		printf("Lua error: %s\n", lua_tostring(L, -1));
		return -1;
	}
	return 0;
}

