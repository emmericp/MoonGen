#!/bin/sh
mkdir -p /mnt/huge
(mount | grep hugetlbfs) > /dev/null || mount -t hugetlbfs nodev /mnt/huge
echo 512 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages

