# MoonGen Packet Generator

MoonGen is a high-speed scriptable packet generator.
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 GBit Ethernet link with 64 Byte packets while using only a single CPU core.
MoonGen can keep this rate even if each packet is modified by a Lua script. It does not rely on tricks like replaying the same buffer.

MoonGen can also receive packets, e.g. to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.

Reading the example script [hello-world.lua](https://github.com/emmericp/MoonGen/blob/master/examples/hello-world.lua) is a good way to learn more about our scripting API.

MoonGen focuses on four main points:

* High performance and multi-core scaling: > 15 millionen packets per second per CPU core
* Flexibility: Each packet is crafted in real time by a user-controlled Lua script
* Precise and accurate timestamping: Timestamping with sub-microsecond precision on commodity hardware
* Precise and accurate rate control: Reliable generation of arbitrary traffic patterns on commodity hardware

You can have a look at [our slides from a recent talk](https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/Slides.pdf) or read an early version of [our paper](http://arxiv.org/abs/1410.3322) [1] for a more detailed discussion of MoonGen's internals.


# Architecture

MoonGen is basically a Lua wrapper around DPDK with utility functions for packet generation.
Users write custom scripts for their experiments. Users are encouraged to make use of hard-coded setup-specific constants in their scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.

The following diagram shows the architecture and how multi-core support is handled.

-> ![Architecture](https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png) <-

Execution begins in the *master task* that must be defined in the user's script.
This task configures queues and filters on the used NICs and then starts one or more *slave tasks*.

Note that Lua does not have any native support for multi threading.
MoonGen therefore starts a new and completely independent LuaJIT VM for each thread that is started.
The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from.
Tasks can only shared state through the underlying library.

The example script [hello-world.lua](https://github.com/emmericp/MoonGen/blob/master/examples/hello-world.lua) shows how this threading model can be used to implement a typical load generation task.
It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic.
A third task is used to categorize and count the incoming packets.


# Hardware Timestamping
Intel commodity NICs like the 82599, X540, and 82580 support time stamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
The NICs achieve sub-microsecond precision and accuracy.

A more detailed evaluation can be found in our [paper](http://arxiv.org/abs/1410.3322) [1].

# Rate Control
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


# API Documentation
MoonGen uses LuaDoc. However, our build system does not yet auto-publish the generated documentation.

TODO: fix this


# Installation

1. Install the dependencies (see below)
2. git submodule update --init
2. ./build.sh
3. ./setup-hugetlbfs.sh
4. Run MoonGen from the build directory

Note: You can also use the script `bind-interfaces.sh` to bind all currently unused NICs (no routing table entry in the system) to DPDK/MoonGen. `build.sh` calls this script automatically.
Use `deps/dpdk/tools/dpdk_nic_bind.py` to unbind NICs from the DPDK driver.


## Dependencies
* gcc
* make
* cmake
* kernel headers (for the DPDK igb-uio driver)

# Examples
MoonGen comes with examples in the examples folder which can be used as a basis for custom scripts.

    ./build/MoonGen ./examples/hello-world.lua 0 0

Note that we recently changed our internal API and some example scripts are outdated or even broken. See [issue #47](https://github.com/emmericp/MoonGen/issues/47) for details.
However, `hello-world.lua` is always kept up to date and uses most important features.

# Frequently Asked Questions

### Which NICs do you support?
Basic functionality is available on all [NICs supported by DPDK](http://dpdk.org/doc/nics).
Hardware timestamping is currently supported and tested on Intel 82599, X540 and 82580 chips.
Hardware rate control is supported and tested on Intel 82599 and X540 chips.


### How is MoonGen different from SnabbSwitch?
[SnabbSwitch](https://github.com/SnabbCo/snabbswitch) is a framework for packet-processing in Lua. 
There are a few important differences:

* MoonGen comes with explicit multi-core support in its API, SnabbSwitch does not
* MoonGen focuses on efficient packet generation, SnabbSwitch is a more generic framework
* Our API is designed for packet-generation tasks, i.e. writing a packet generator script for MoonGen is a lot easier than writing one for SnabbSwitch
* We implement driver-like functionality for hardware functions for packet generators: timestamping, rate control, and packet filtering
* SnabbSwitch re-implements the NIC driver in Lua, we rely on the DPDK driver for most parts


### Why does MoonGen use DPDK instead of SnabbSwitch as driver?
We decided for DPDK as back end for the following reasons

* DPDK is faster for raw packet IO. This is not really a drawback for the use cases SnabbSwitch is designed for where IO is only a small part of the processing. However, for packet generation, especially with small packets, the share of packet IO is significant and the performance of SnabbSwitch is not sufficient here.
* DPDK provides a stable and mature code base while SnabbSwitch is a relatively young project.
* DPDK currently supports more NICs (with stable and mature drivers) than SnabbSwitch. (We do not want to write our own drivers or debug existing ones.)
* Lack of multi-core support. (Only possible by starting SnabbSwitch more than once.)

Note that this might change. Using DPDK also comes with disadvantages like its bloated build system and configuration.

# References
[1] Paul Emmerich, Florian Wohlfart, Daniel Raumer, and Georg Carle. MoonGen: A Scriptable High-Speed Packet Generator. Preprint available: [arXiv:1410.3322](http://arxiv.org/abs/1410.3322)  
