#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")
cd dpdk
make -j 8 install T=x86_64-default-linuxapp-gcc
modprobe uio
(lsmod | grep igb_uio > /dev/null) || insmod ./x86_64-default-linuxapp-gcc/kmod/igb_uio.ko
for id in $(tools/igb_uio_bind.py --status | grep -v Active | grep unused=igb_uio | cut -f 1 -d " ")
do
	tools/igb_uio_bind.py --bind=igb_uio $id
done
cd ../build
cmake ..
make
)

