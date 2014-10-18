# MoonGen Packet Generator

MoonGen is a high-speed scriptable packet generator.
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 GBit Ethernet link with 64 Byte packets while using only a single CPU core.
MoonGen can keep this rate even if each packet is modified by a Lua script. It does not simply replay the same buffer.

MoonGen can also receive packets, e.g. to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.

You can read [our paper](http://arxiv.org/abs/1410.3322) for more details about MoonGen.

# Hardware Features
MoonGen utilizes advanced hardware features of commodity NICs to implement time stamping and rate control.

## Time Stamping
Intel commodity NICs like the 82599, X540, and 82580 support time stamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
The NICs achieve sub-microsecond precision and accuracy.

Read more: paper [1], wiki page (TODO)

## Rate Control
Intel 10 GbE NICs (82599 and X540) support rate control in hardware.
This can be used to generate CBR or bursty traffic with precise inter-departure times.

Read more: paper [1], wiki page (TODO)

# Reliable Software Rate Control for Complex Traffic Patterns
Generating precise inter-departure times in software at high packet rates is hard.
See our paper [1] for more details.
The hardware supports only CBR but other traffic patterns, especially a Poisson distribution, are desirable.

The problem that software rate control faces is that transmitted packets go through a queue on the NIC.
Generating an 'empty space' on the wire means that the queue must be empty, i.e. packets need to be placed individually in the queue instead of batches.
The latency between sending packets to the NICs needs to be controlled with nanosecond-precision - a challenging task for the software.
You can find some measurements of software-based generators in [1].

We can circumvent this problem by sendind bad packets in the space between packets instead of trying to send nothing.
A bad packet, in this context, is a packet that is not accepted by the DuT (device under test) and filtered in hardware before it reaches the software.
Such a packet could be one with a bad CRC, an invalid length, or simply with a different destination MAC.
If the DuT's NIC does not drop this packet in hardware without affecting the running software or hardware queues or if a hardware device is to be tested, then a switch can be used to remove these packets from the stream to generate real spacing on the wire.
The effects of the switch on the packet spacing needs to be analyzed carefully, e.g. with MoonGen's inter-arrival.lua example script, in this case.
This is currently not implemented but one of the next items on our todo list.


# Documentation
MoonGen uses LuaDoc. However, our build system does not yet auto-publish the generated documentation.

TODO: fix this


# Installation

1. Install the dependencies (see below)
2. ./build.sh
3. ./setup-hugetlbfs.sh
4. Run MoonGen from the build directory (install target coming soon)

## Dependencies
* gcc
* make
* cmake
* kernel headers (for the DPDK ixgbe-uio driver)
* libluajit-2.0.3

# Examples
MoonGen comes with examples in the examples folder which can be used as a basis for custom scripts.

    ./MoonGen ../examples/l2-load-latency.lua 0 0

# Frequently Asked Questions

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

# References
[1] Paul Emmerich, Florian Wohlfart, Daniel Raumer, and Georg Carle. MoonGen: A Scriptable High-Speed Packet Generator. Submitted to PAM 2015. Preprint available: [arXiv:1410.3322](http://arxiv.org/abs/1410.3322)  
