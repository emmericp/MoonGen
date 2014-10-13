#MoonGen Packet Generator

MoonGen is a high-speed scriptable packet generator.
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 GBit Ethernet link with 64 Byte packets while using only a single CPU core.

MoonGen utilizes advanced hardware features of commodity NICs to implement
time stamping with sub-microsecond precision and accuracy. MoonGen also
supports rate control on Intel 10 GbE NICs that allows us to generate CBR
traffic and bursty traffic with precise inter-departure times.


MoonGen can also receive packets, e.g. to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.


#Examples
MoonGen comes with examples in the examples folder which can be used as a basis for custom scripts.

    ./MoonGen ../examples/l2-load-latency.lua 0 0

#Documentation
MoonGen uses LuaDoc. However, our build system does not yet auto-publish the generated documentation.

TODO: fix this


#Installation

1. Install the dependencies (see below)
2. ./build.sh
3. ./setup-hugetlbfs.sh
4. Run MoonGen from the build directory (install target coming soon)

##Dependencies
* gcc
* make
* cmake
* kernel headers (for the DPDK ixgbe-uio driver)
* libluajit-2.0.3

#Frequently Asked Questions

### Which NICs do you support?
Basic functionality is available on all [NICs supported by DPDK](http://dpdk.org/doc/nics).
Hardware timestamping is currently supported and tested on Intel 82599, X540 and 82580 chips.
Rate control is supported and tested on Intel 82599 and X540 chips.


### How is MoonGen different from SnabbSwitch?
[SnabbSwitch](https://github.com/SnabbCo/snabbswitch) is a framework for packet-processing in Lua. 
There are a few important differences:

* MoonGen focuses on efficient packet generation, SnabbSwitch is a more generic framework
* Our API is designed for packet-generation tasks, i.e. writing a packet generator script for MoonGen is a lot easier than writing one for SnabbSwitch
* We implement driver-like functionality for hardware functions for packet generators: timestamping, rate control, and packet filtering
* SnabbSwitch re-implements the NIC driver in Lua, we rely on the DPDK driver for most parts

This means that SnabbSwitch could be used as a back end for MoonGen.

### Why does MoonGen use DPDK instead of SnabbSwitch as driver?
We decided for DPDK as back end for the following reasons
* DPDK is slightly faster for raw packet IO. This is not really a drawback for the use cases SnabbSwitch is designed for where IO is only a small part of the processing. However, for packet generation the share of packet IO is significant.
* DPDK provides a stable and mature code base while SnabbSwitch is a relatively young project
* DPDK currently supports more NICs (with stable and mature drivers) than SnabbSwitch (We do not want to write our own drivers or debug existing ones)

Note that this might change. Using DPDK also comes with disadvantages like its bloated build system and configuration.

