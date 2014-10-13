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

##Dependencies

* gcc
* make
* cmake
* kernel headers (for the DPDK ixgbe-uio driver)
* libluajit-2.0.3

##Installation

1. Install the dependencies
2. ./build.sh
3. ./setup-hugetlbfs.sh
4. Run MoonGen from the build directory (install target coming soon)

##Examples
MoonGen comes with examples in the examples folder which can be used as a basis for custom scripts.

    ./MoonGen ../examples/l2-load-latency.lua 0 0

#Documentation
MoonGen uses LuaDoc. However, our build system does not yet auto-publish the generated documentation.

TODO: fix this


