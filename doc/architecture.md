\page architecture Architecture
\tableofcontents


MoonGen is basically a Lua wrapper around DPDK with utility functions for packet generation. Users write custom scripts for their experiments. It is recommended to make use of hard-coded setup-specific constants in your scripts. The script is the configuration, it is beside the point to write a complicated configuration interface for a script.

The following diagram shows the architecture and how multi-core support is handled.

<p align="center">
<img alt="Architecture" src="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png" srcset="https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture.png 1x, https://raw.githubusercontent.com/emmericp/MoonGen/master/doc/img/moongen-architecture@2x.png 2x"/>
</p>

Execution begins in the master task that must be defined in the user's script. This task configures queues and filters on the used NICs and then starts one or more slave tasks.

Note that Lua does not have any native support for multi threading. MoonGen therefore starts a new and completely independent LuaJIT VM for each thread. The new VMs receive serialized arguments: the function to execute and arguments like the queue to send packets from. Threads only share state through the underlying library.

The example script quality-of-service-test.lua shows how this threading model can be used to implement a typical load generation task. It implements a QoS test by sending two different types of packets and measures their throughput and latency. It does so by starting two packet generation tasks: one for the background traffic and one for the prioritized traffic. A third task is used to categorize and count the incoming packets.
