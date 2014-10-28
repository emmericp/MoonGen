#!/bin/bash

# TODO: this should probably be a makefile
# TODO: install target
(
cd $(dirname "${BASH_SOURCE[0]}")
cd luajit
make -j 8 'CFLAGS=-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT'
make install DESTDIR=/root/MoonGen/luajit
cd ..
cd dpdk
make -j 8 install T=x86_64-native-linuxapp-gcc
modprobe uio
(lsmod | grep igb_uio > /dev/null) || insmod ./x86_64-native-linuxapp-gcc/kmod/igb_uio.ko
for id in $(tools/dpdk_nic_bind.py --status | grep -v Active | grep unused=igb_uio | cut -f 1 -d " ")
do
	tools/dpdk_nic_bind.py --bind=igb_uio $id
done
cd ../build
cmake ..
make 
)

