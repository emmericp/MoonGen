### TL;DR
LuaJIT + DPDK = fast and flexible packet generator for 10 GBit Ethernet and beyond.

MoonGen uses hardware features for accurate and precise latency measurements and rate control.

You have to write a simple script for your use case.
Read [quality-of-service-test.lua](https://github.com/emmericp/MoonGen/blob/master/examples/quality-of-service-test.lua) to get started.

Detailed evaluation: [Paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) ([BibTeX entry](http://adsabs.harvard.edu/cgi-bin/nph-bib_query?bibcode=2014arXiv1410.3322E&data_type=BIBTEX&db_key=PRE&nocookieset=1))

# MoonGen Packet Generator

MoonGen is a high-speed scriptable packet generator.
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 GBit Ethernet link with 64 Byte packets while using only a single CPU core.
MoonGen can achieve this rate even if each packet is modified by a Lua script. It does not rely on tricks like replaying the same buffer.

MoonGen can also receive packets, e.g. to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.

Reading the example script [quality-of-service-test.lua](https://github.com/emmericp/MoonGen/blob/master/examples/quality-of-service-test.lua) is a good way to learn more about our scripting API as this script uses most features of MoonGen.

MoonGen focuses on four main points:

* High performance and multi-core scaling: > 15 million packets per second per CPU core
* Flexibility: Each packet is crafted in real time by a user-provided Lua script
* Precise and accurate timestamping: Timestamping with sub-microsecond precision on commodity hardware
* Precise and accurate rate control: Reliable generation of arbitrary traffic patterns on commodity hardware

You can have a look at [our slides from a recent talk](https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/Slides.pdf) or read a draft of [our paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) [1] for a more detailed discussion of MoonGen's internals.


# Architecture

MoonGen is basically a Lua wrapper around DPDK with utility functions for packet generation.
Users write custom scripts for their experiments. It is recommended to make use of hard-coded setup-specific constants in your scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.

The following diagram shows the architecture and how multi-core support is handled.

<p align="center">
<img alt="Architecture" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture@2x.png 2x"/>
</p>

Execution begins in the *master task* that must be defined in the user's script.
This task configures queues and filters on the used NICs and then starts one or more *slave tasks*.

Note that Lua does not have any native support for multi threading.
MoonGen therefore starts a new and completely independent LuaJIT VM for each thread.
The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from.
Threads only share state through the underlying library.

The example script [quality-of-service-test.lua](https://github.com/emmericp/MoonGen/blob/master/examples/quality-of-service-test.lua) shows how this threading model can be used to implement a typical load generation task.
It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic.
A third task is used to categorize and count the incoming packets.


# Hardware Timestamping
Intel commodity NICs like the 82599, X540, and 82580 support time stamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
The NICs achieve sub-microsecond precision and accuracy.

A more detailed evaluation can be found in [our paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) [1].

# Rate Control
Precise control of inter-packet gaps is an important feature for reproducible tests.
Bad rate control, e.g. generation of undesired micro-bursts, can affect the behavior of a device under test [1].
However, software packet generators are usually bad at controlling the inter-packet gaps [2].

The following diagram illustrates how a typical software packet generator tries to control the packet rate.

<p align="center">
<img alt="Software Rate Control" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-traditional-software.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-traditional-software.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-traditional-software.png@2x 2x"/>
</p>

It simply tries to wait for a specified time after sending a packet.
Network APIs often abstract NICs in a way that indicates that the API pushes a packet to the NIC, so this technique might seem reasonable.
However, NICs do not work that way. Sending a packet to the API merely places it in a queue in the main memory.
It is now up to the NIC (which may or may not be notified by the API about the new packet immediately) to fetch and transmit the packet asynchronously at a convenient time.

This means that trying to push packets to a NIC is futile.
This is especially important at rates above 1 GBit/s where nanosecond-level precision is required (length of a minimal sized packet at 10 GBit/s: 67.2 nanoseconds).
Sending a single packet requires at least two round trips across the PCIe bus: One to notify the NIC about the updated queue, one for the NIC to fetch the packet. Each PCIe operation introduces latencies and jitter in the nanosecond-range.

Another problem with this approach is that the queues, and therefore batch processing, cannot be used.
However, batch processing is an important technique to achieve line rate at high packet rates [3].

MoonGen therefore implements two ways to prevent this problem.

## Hardware Rate Control

Intel 10 GbE NICs (82599 and X540) support rate control in hardware.
This can be used to generate CBR or bursty traffic with precise inter-departure times.

[Our paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) [1] features a detailed evaluation of this feature and compares it to software methods.

## Better Software Rate Control
The hardware supports only CBR traffic. Other traffic patterns, especially a Poisson distribution, are desirable.

The problem that software rate control faces is that it needs to generate an 'empty space' on the wire.
We circumvent this problem by sending bad packets in the space between packets instead of trying to send nothing.
The following diagram illustrates this concept.

<p align="center">
<img alt="Better Software Rate Control" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-moongen-software.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-moongen-software.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/ratecontrol-moongen-software@2x.png 2x"/>
</p>

A bad packet is a packet that is not accepted by the DuT (device under test) and filtered in hardware before it reaches the software. These packets are shaded in the figure above.
We currently use packets with an invalid CRC and an invalid length if necessary.
All common NICs drop such packets immediately in hardware as further processing of a corrupted packet is pointless.
This does not affect the running software.
[Our paper](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf) contains a measurement which shows that this is the case.

If the DuT's NIC does not do this or if a hardware device is to be tested, then a switch can be used to remove these packets from the stream to generate 'real' space on the wire.
The effects of the switch on the packet spacing needs to be analyzed carefully, e.g. with MoonGen's inter-arrival.lua example script.



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

    ./build/MoonGen ./examples/quality-of-service-test.lua 0 1

The two command line arguments are the transmission and reception ports. MoonGen prints all available ports on startup, so adjust this if necessary.

Note that we recently changed our internal API and some example scripts are outdated or even broken. See [issue #47](https://github.com/emmericp/MoonGen/issues/47) for details.
However, `quality-of-service-test.lua` is always kept up to date and uses most important features.

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
* We implement driver-like functionality for hardware functions required by packet generators: timestamping, rate control, and packet filtering
* SnabbSwitch reimplements the NIC driver in Lua, we rely on the DPDK driver for most parts


### Why does MoonGen use DPDK instead of SnabbSwitch as driver?
We decided for DPDK as back end for the following reasons:

* DPDK is faster for raw packet IO. This is not really a drawback for the use cases SnabbSwitch is designed for where IO is only a small part of the processing. However, for packet generation, especially with small packets, the share of packet IO is significant and the performance of SnabbSwitch is not sufficient here.
* DPDK provides a stable and mature code base whereas SnabbSwitch is a relatively young project.
* DPDK currently supports more NICs (with stable and mature drivers) than SnabbSwitch. (We do not want to write our own drivers or debug existing ones.)
* Lack of multi-core support. (Only possible by starting SnabbSwitch more than once.)

Note that this might change. Using DPDK also comes with disadvantages like its bloated build system and configuration.

# References
[1] Paul Emmerich, Sebastian Gallenmüller, Florian Wohlfart, Daniel Raumer, and Georg Carle. MoonGen: A Scriptable High-Speed Packet Generator, 2015. Draft. Conference TBD. [Preprint available](http://arxiv.org/ftp/arxiv/papers/1410/1410.3322.pdf).  [BibTeX](http://adsabs.harvard.edu/cgi-bin/nph-bib_query?bibcode=2014arXiv1410.3322E&data_type=BIBTEX&db_key=PRE&nocookieset=1).

[2] Alessio Botta, Alberto Dainotti, and Antonio Pescapé. Do you trust your software-based traffic generator? In *IEEE Communications Magazine*, 48(9):158–165, 2010.

[3] Luigi Rizzo. netmap: a novel framework for fast packet I/O. In *USENIX Annual Technical Conference*, pages 101–112, 2012.
