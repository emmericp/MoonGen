### TL;DR
LuaJIT + DPDK = fast and flexible packet generator for 10 Gbit/s Ethernet and beyond.

MoonGen uses hardware features for accurate and precise latency measurements and rate control.

You have to write a simple script for your use case.
The example [l3-load-latency.lua](https://github.com/emmericp/MoonGen/blob/master/examples/l3-load-latency.lua) is a good starting point as it makes use of a lot of different features of MoonGen.

[API documentation](http://scholzd.github.io/MoonGen/index.html) (preliminary)

Detailed evaluation: [Paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) (IMC 2015, [BibTeX entry](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015-BibTeX.txt))

# MoonGen Packet Generator

MoonGen is a scriptable high-speed packet generator built on [libmoon](https://github.com/libmoon/libmoon).
The whole load generator is controlled by a Lua script: all packets that are sent are crafted by a user-provided script.
Thanks to the incredibly fast LuaJIT VM and the packet processing library DPDK, it can saturate a 10 Gbit/s Ethernet link with 64 Byte packets while using only a single CPU core.
MoonGen can achieve this rate even if each packet is modified by a Lua script. It does not rely on tricks like replaying the same buffer.

MoonGen can also receive packets, e.g., to check which packets are dropped by a
system under test. As the reception is also fully under control of the user's
Lua script, it can be used to implement advanced test scripts. E.g. one can use
two instances of MoonGen that establish a connection with each other. This
setup can be used to benchmark middle-boxes like firewalls.

Reading the example script [l3-load-latency.lua](https://github.com/emmericp/MoonGen/blob/master/examples/l3-load-latency.lua?ts=4) or [quality-of-service-test.lua](https://github.com/emmericp/MoonGen/blob/master/examples/quality-of-service-test.lua?ts=4) is a good way to learn more about our scripting API as these scripts uses most features of MoonGen.

MoonGen focuses on four main points:

* High performance and multi-core scaling: > 20 million packets per second per CPU core
* Flexibility: Each packet is crafted in real time by a user-provided Lua script
* Precise and accurate timestamping: Timestamping with sub-microsecond precision on commodity hardware
* Precise and accurate rate control: Reliable generation of arbitrary traffic patterns on commodity hardware

You can have a look at [our slides from a talk](https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/Slides.pdf) or read [our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) [1] for a more detailed discussion of MoonGen's internals.


# Architecture

MoonGen is built on [libmoon](https://github.com/libmoon/libmoon), a Lua wrapper for DPDK.


Users write custom scripts for their experiments. It is recommended to make use of hard-coded setup-specific constants in your scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.

The following diagram shows the architecture and how multi-core support is handled.

<p align="center">
<img alt="Architecture" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture@2x.png 2x"/>
</p>

Execution begins in the *master task* that must be defined in the userscript.
This task configures queues and filters on the used NICs and then starts one or more *slave tasks*.

Note that Lua does not have any native support for multi-threading.
MoonGen therefore starts a new and completely independent LuaJIT VM for each thread.
The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from.
Threads only share state through the underlying library.

The example script [quality-of-service-test.lua](https://github.com/emmericp/MoonGen/blob/master/examples/quality-of-service-test.lua?ts=4) shows how this threading model can be used to implement a typical load generation task.
It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic.
A third task is used to categorize and count the incoming packets.


# Hardware Timestamping
Intel commodity NICs from the igb, ixgbe, and i40e families support timestamping in hardware for both transmitted and received packets.
The NICs implement this to support the IEEE 1588 PTP protocol, but this feature can be used to timestamp almost arbitrary UDP packets.
MoonGen achieves a precision and accuracy of below 100 ns.

Use ``test-timestamping-capabilities.lua`` in ``examples/timestamping-tests`` to test your NIC's timestamping capabilities.

A more detailed evaluation can be found in [our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) [1].

# Rate Control
Precise control of inter-packet gaps is an important feature for reproducible tests.
Bad rate control, e.g., generation of undesired micro-bursts, can affect the behavior of a device under test [1].
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
This is especially important at rates above 1 Gbit/s where nanosecond-level precision is required (length of a minimal sized packet at 10 Gbit/s: 67.2 nanoseconds).
Sending a single packet requires at least two round trips across the PCIe bus: One to notify the NIC about the updated queue, one for the NIC to fetch the packet. Each PCIe operation introduces latencies and jitter in the nanosecond-range.

Another problem with this approach is that the queues, and therefore batch processing, cannot be used.
However, batch processing is an important technique to achieve line rate at high packet rates [3].

MoonGen therefore implements two ways to prevent this problem.

## Hardware Rate Control

Intel 10 and 40 GbE NICs (ixgbe and i40e) support rate control in hardware.
This can be used to generate CBR or bursty traffic with precise inter-departure times.

[Our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) [1] features a detailed evaluation of this feature and compares it to software methods.

## Better Software Rate Control
The hardware supports only CBR traffic. Other traffic patterns, especially a Poisson process, are desirable.

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
[Our paper](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf) contains a measurement which shows that this is the case.

If the DuT's NIC does not do this or if a hardware device is to be tested, then a switch can be used to remove these packets from the stream to generate 'real' space on the wire.
The effects of the switch on the packet spacing needs to be analyzed carefully, e.g., with MoonGen's inter-arrival.lua example script.



# API Documentation
[Preliminary documentation](http://scholzd.github.io/MoonGen/index.html)


# Installation

1. Install the dependencies (see below)
2. ./build.sh
3. sudo ./bind-interfaces.sh
4. sudo ./setup-hugetlbfs.sh
5. sudo ./build/MoonGen examples/l3-load-latency.lua 0 1

Note: You need to bind NICs to DPDK to use them. `bind-interfaces.sh` does this for all unused NICs (no routing table entry in the system).
Use `libmoon/deps/dpdk/tools/dpdk-devbind.py` to manage NICs manually.


## Dependencies
* gcc >= 4.8
* make
* cmake
* kernel headers (for the DPDK igb-uio driver)
* lspci (for `dpdk-devbind.py`)

# Examples
MoonGen comes with examples in the examples folder which can be used as a basis for custom scripts.

    ./build/MoonGen ./examples/l3-load-latency.lua 0 1

The two command line arguments are the transmission and reception ports. MoonGen prints all available ports on startup, so adjust this if necessary.

You can also check out the examples of the [libmoon](https://github.com/libmoon/libmoon) project.
All libmoon scripts are also valid MoonGen scripts as MoonGen extends libmoon.

# Frequently Asked Questions

### Which NICs do you support?
Basic functionality is available on all [NICs supported by DPDK](http://dpdk.org/doc/nics).
Hardware timestamping is currently supported and tested on Intel igb, ixgbe, and i40e NICs. However, support for specific features vary between models.
Use ``test-timestamping-capabilities.lua`` in ``examples/timestamping-tests`` to find out what your NIC supports.
Hardware rate control is supported and tested on Intel ixgbe and i40e NICs.

### What's the difference between MoonGen and libmoon?
MoonGen builds on [libmoon](https://github.com/libmoon/libmoon) by extending it with features for packet generators such as software rate control and software timestamping.

If you want to write a packet generator or test your application: use MoonGen.
If you want to prototype DPDK applications: use [libmoon](https://github.com/libmoon/libmoon).


# References
[1] Paul Emmerich, Sebastian Gallenmüller, Daniel Raumer, Florian Wohlfart, and Georg Carle. MoonGen: A Scriptable High-Speed Packet Generator, 2015. IMC 2015. [Available online](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015.pdf).  [BibTeX](http://www.net.in.tum.de/fileadmin/bibtex/publications/papers/MoonGen_IMC2015-BibTeX.txt).

[2] Alessio Botta, Alberto Dainotti, and Antonio Pescapé. Do you trust your software-based traffic generator? In *IEEE Communications Magazine*, 48(9):158–165, 2010.

[3] Luigi Rizzo. netmap: a novel framework for fast packet I/O. In *USENIX Annual Technical Conference*, pages 101–112, 2012.
