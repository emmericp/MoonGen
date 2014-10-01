#ifndef TASK_H__
#define TASK_H__

#include <luajit-2.0/lauxlib.h>
#include <luajit-2.0/lualib.h>

lua_State* launch_lua(char* file);

void launch_lua_core(int core, const char* file, int argc, const char** argv);

#endif
