\mainpage
\tableofcontents
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



