#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdbool.h>

#include <rte_launch.h>

#include "task.h"

static const char* find_path(const char* file) {
	// TODO: search file
	return file;
}

lua_State* launch_lua(const char* file) {
	lua_State* L = luaL_newstate();
	luaL_openlibs(L);
	if (luaL_loadfile(L, find_path(file))) {
		printf("could not load file: %s\n", lua_tostring(L, -1));
		return NULL;
	}
	return L;
}




int lua_core_main(void* arg) {
	int rc = -1;
	struct lua_core_config* cfg = (struct lua_core_config*) arg;
	lua_State* L = launch_lua(cfg->file);
	if (!L) {
		goto error;
	}
	lua_pushstring(L, "slave");
	for (int i = 0; i < cfg->argc; i++) {
		struct lua_core_arg* arg = cfg->argv[i];
		switch (arg->arg_type) {
			case ARG_TYPE_STRING:
				lua_pushstring(L, arg->arg.str);
				break;
			case ARG_TYPE_NUMBER:
				lua_pushnumber(L, arg->arg.number);
				break;
			case ARG_TYPE_BOOLEAN:
				lua_pushboolean(L, arg->arg.boolean);
				break;
			case ARG_TYPE_POINTER:
				lua_pushlightuserdata(L, arg->arg.ptr);
				break;
			case ARG_TYPE_NIL:
				lua_pushnil(L);
				break;
		}
	}
	if (lua_pcall(L, cfg->argc + 1, 0, 0)) {
		printf("Lua error: %s\n", lua_tostring(L, -1));
		goto error;
	}
	rc = 0;
error:
	free(cfg->file);
	for (int i = 0; i < cfg->argc; i++) {
		struct lua_core_arg* arg = cfg->argv[i];
		if (arg->arg_type == ARG_TYPE_STRING) {
			free(arg->arg.str);
		}
		free(arg);
	}
	free(cfg);
	return rc;
}

void launch_lua_core(int core, const char* file, int argc, struct lua_core_arg* argv[]) {
	struct lua_core_config* cfg = (struct lua_core_config*) malloc(sizeof(struct lua_core_config));
	cfg->file = (char*) malloc(strlen(file) + 1);
	strcpy(cfg->file, file);
	cfg->argc = argc;
	cfg->argv = (struct lua_core_arg**) malloc(argc * sizeof(struct lua_core_arg*));
	for (int i = 0; i < argc; i++) {
		struct lua_core_arg* arg = cfg->argv[i] = (struct lua_core_arg*) malloc(sizeof(struct lua_core_arg));
		arg->arg_type = argv[i]->arg_type;
		switch (arg->arg_type) {
			case ARG_TYPE_STRING:
				arg->arg.str = malloc(strlen(argv[i]->arg.str) + 1);
				strcpy(arg->arg.str, argv[i]->arg.str);
				break;
			case ARG_TYPE_NUMBER:
				arg->arg.number = argv[i]->arg.number;
				break;
			case ARG_TYPE_BOOLEAN:
				arg->arg.boolean = argv[i]->arg.boolean;
				break;
			case ARG_TYPE_POINTER:
				arg->arg.ptr = argv[i]->arg.ptr;
				break;
			case ARG_TYPE_NIL:
				break;
		}
	}
	rte_eal_remote_launch(&lua_core_main, cfg, core);
}

