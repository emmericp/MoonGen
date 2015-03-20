#ifndef TASK_H__
#define TASK_H__

#include <stdbool.h>
#include <stdint.h>

#include <lauxlib.h>
#include <lualib.h>

struct lua_core_arg {
	enum { ARG_TYPE_STRING, ARG_TYPE_NUMBER, ARG_TYPE_BOOLEAN, ARG_TYPE_POINTER, ARG_TYPE_NIL, ARG_TYPE_OBJECT } arg_type;
	union {
		char* str;
		double number;
		void* ptr;
		bool boolean;
	} arg;
};

struct lua_core_config {
	int argc;
	uint64_t task_id;
	struct lua_core_arg** argv;
};

lua_State* launch_lua();

void launch_lua_core(int core, uint64_t task_id, int argc, struct lua_core_arg* argv[]);

#endif
