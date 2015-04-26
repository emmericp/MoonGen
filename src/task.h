#ifndef TASK_H__
#define TASK_H__

#include <stdbool.h>
#include <stdint.h>

#include <lauxlib.h>
#include <lualib.h>

struct lua_core_config {
	uint64_t task_id;
	char* userscript;
	char* args;
};

lua_State* launch_lua();

void launch_lua_core(int core, uint64_t task_id, char* userscript, char* args);

#endif
