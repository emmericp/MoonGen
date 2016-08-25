\page faq Frequently Asked Questions
\tableofcontents

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
