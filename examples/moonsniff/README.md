# MoonSniff: How-to

## What is MoonSniff for?

MoonSniff consists of several scripts and also extensions to the MoonGen core which allow measuring latencies of packets with an accuracy (trueness) of ±20 ns. This is possible with just commodity hardware. The test-setup we describe later on also makes sure that measurements have no impact on the system behavior in terms of jitter or additional latencies.

Basically, it can be seen as a cheaper alternative to buying professional DAQ packet capture cards.

## Which hardware is needed to run MoonSniff?
In order to run MoonSniff you need the following hardware:

- Traffic Generator: Server with NIC (MoonGen compatible for easiest use)
- Sniffer: Server with X552 Ethernet Controller with two 10 GbE ports
  
  Note: The Intel Xeon Processor D-1500 family has onboard X552 NIC
- Splitter: 2x Passive optical fiber splitter
- Optical: 6x Optical fiber cable
- DUT: The device you want to test (switch, software forwarder, router, cable, etc.)


## How to setup MoonSniff?
One possible test setup is shown below:

    Traffic Generator                                        Device Under Test
    |-----------------|                                      |-----------------|
    |                 |               Splitter               |                 |
    |             Out |----------------x---------------------| In              |
    |                 |                |                     |                 |
    |              In |----------------]----x----------------| Out             |
    |                 |                |    |                |                 |
    |-----------------|                |    |                |-----------------|
                                       |    |
                                 |-----------------|
                                 |   Pre    Post   |
                                 |                 |
                                 |                 |
                                 |                 |
                                 |                 |
                                 |-----------------|
                                 Sniffer

The traffic generator will create packets which are sent towards the DUT. The packets will be processed by the DUT and then sent back. Due to the splitter, the sniffer will receive two copies of each packet. One on the pre interface (packet before it entered the DUT) and one on the post interface (packet after it traversed the DUT). The sniffer timestamps both packets and can compute the total time each packet has spent inside the DUT. It can then create histograms showing the distribution of latencies and mean/variance of the latencies.

## How to use MoonSniff?
MoonSniff provides scripts for the traffic generator, DUT, and sniffer. All scripts can be found in the ``examples/moonsniff/`` directory.

To see all options supported by a script, execute it with the ``-h`` or ``--help`` flag.


### Quick example
The following example describes how to use MoonSniff for the setup described above.

On the traffic generator:

    ./build/MoonGen examples/moonsniff/traffic-gen.lua 0 1

On the DUT:

    ./build/MoonGen examples/moonsniff/test-dev.lua 0 1

On the sniffer:

    ./build/MoonGen examples/moonsniff/traffic-gen.lua 0 1 --live


### MoonSniff Modes
MoonSniff runs in three different modes.

1. Live Mode

   This mode is meant for fast average latency estimation and is also helpful as a first check if everything works as expected. Has comparably low precision.
   
   **Important:** This mode requires all packets to feature an identifier. See the section about identifiers.

   Execute the following for the Live Mode:
   
        ./build/MoonGen examples/moonsniff/traffic-gen.lua 0 1 --live

2. MSCAP Mode
   
   This mode creates full histograms for longer time intervals. To achieve maximum precision this mode is split into a sniffing and a post-processing phase. The memory consumption is reduced by using MoonSniff's MSCAP format which instead of storing full packets, stores only identifiers as well as timestamps. The first phase generates two files, one pre-DUT and one post-DUT file. In the second phase packets from both files are matched together and the latencies are computed.
   
   **Important:** This mode requires all packets to feature an identifier. See the section about identifiers.

   Execute the following for the MSCAP Mode:

        # MSCAP Mode is the default mode
        # generates latencies-pre.mscap, latencies-post.mscap, and latencies-stats.csv
        ./build/MoonGen examples/moonsniff/traffic-gen.lua 0 1

        # use generated files to compute latency-histogram
        # generates hist.csv
        ./build/MoonGen examples/moonsniff/post-processing.lua -i latencies-pre.mscap -s latencies-post.mscap

3. PCAP Mode

   This mode also creates full histograms. Contrary to the MSCAP mode, it does not require identifiers within packets. Packets are captured as a whole, and the user can provide a user defined function (UDF) which creates an identifier based on selected parts of the packet. The UDF is a Lua script which can make use of all features of MoonGen/libmoon, especially the packet API. The UDF can handle pre and post packets differently, hence, you can (with corresponding effort) compensate all deterministic changes made by the DUT to packets. E.g. a router changes IP-addresses, but if you know your routing table you can reverse this process and generate the same identifier. To change the UDF and to see a simple example, have a look at the [pkt-matcher.lua](pkt-matcher.lua) file.

   Apart from this distinction, this mode operates the same way as the MSCAP mode.
   
   **Important:** As whole packets are captured the resulting files are very large. An SSD is recommended for high data-rates.  

    Execute the following for the PCAP Mode:

        # generates latencies-pre.pcap, latencies-post.pcap, and latencies-stats.csv
        ./build/MoonGen examples/moonsniff/traffic-gen.lua 0 1 --capture

        # use generated files to compute latency-histogram
        # generates hist.csv
        ./build/MoonGen examples/moonsniff/post-processing.lua -i latencies-pre.pcap -s latencies-post.pcap

### Identifiers
Identifiers are used by two modes to efficiently match corresponding pre and post packets. The way it is currently handled can be seen in the [traffic-gen.lua](traffic-gen.lua) file.

| UDP-IPv4 headers | identifier | MoonSniff type |
| ---------------- | ---------- | -------------- |
| x bytes          | 4 bytes    | 1 byte         |

MoonSniff type is set to: ``0b01010101``.
The type is used to filter packets which do not belong to our generated traffic.


## Further Information
To assist further automation of MoonSniff we provide some example scripts that simplify measurement series in [this](https://github.com/AP-Frank/moonsniff-scripts) repository. It also provides a script to visualize the generated histograms.