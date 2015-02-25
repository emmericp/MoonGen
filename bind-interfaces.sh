#!/bin/bash

(
cd $(dirname "${BASH_SOURCE[0]}")
cd deps/dpdk

modprobe uio
(lsmod | grep igb_uio > /dev/null) || insmod ./x86_64-native-linuxapp-gcc/kmod/igb_uio.ko

i=0
for id in $(tools/dpdk_nic_bind.py --status | grep -v Active | grep unused=igb_uio | cut -f 1 -d " ")
do
	echo "Binding interface $id to DPDK"
	tools/dpdk_nic_bind.py --bind=igb_uio $id
	i=$(($i+1))
done

if [[ $i == 0 ]]
then
	echo "Could not find any inactive interfaces to bind to DPDK. Note that this script does not bind interfaces that are in use by the OS."
	echo "Delete IP addresses from interfaces you would like to use with MoonGen and run this script again."
	echo "You can also use the script dpdk_nic_bind.py in deps/dpdk/tools manually to manage interfaces used by MoonGen and the OS."
fi

)

