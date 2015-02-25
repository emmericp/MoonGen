#!/bin/bash

# TODO: this should probably be a makefile
# TODO: install target
(
cd $(dirname "${BASH_SOURCE[0]}")
cd deps/luajit
if [[ ! -e Makefile ]]
then
	echo "ERROR: LuaJIT submodule not initialized"
	echo "Please run git submodule update --init"
	exit 1
fi
make -j 8 'CFLAGS=-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
make install DESTDIR=$(pwd)
cd ../dpdk
make -j 8 install T=x86_64-native-linuxapp-gcc
../../bind-interfaces.sh
cd ../../build
cmake ..
make
)

