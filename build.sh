#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")
git submodule update --init --recursive

(
cd phobos/deps/luajit
make -j 16 BUILDMODE=static 'CFLAGS=-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
make install DESTDIR=$(pwd)
)

(
cd phobos/deps/dpdk
make -j 16 install T=x86_64-native-linuxapp-gcc
)

(
cd build
cmake ..
make -j 16
)

echo Trying to bind interfaces, this will fail if you are not root
echo Try "sudo ./bind-interfaces.sh" if this step fails
./bind-interfaces.sh
)

