# --------------------------------------------------------------------------- #
#                                                                             #
#  --------------           --------------   --------------   -----     ----- #
#  |    -----   |           |   -----|   |   |            |   |   |-|   |   | #
#  |    |   |   |           |   |    |   |   |    ---------   |     -|  |   | #
#  |    |   |   |           |   |    -----   |    |           |      -| |   | #
#  |    -----   |           |   |            |    ---------   |       -||   | #
#  |    ---------  -------  |   |            |            |   |   |-|  -|   | #
#  |    |          |     |  |   |  -------   |    ---------   |   | -|      | #
#  |    |          -------  |   |  |     |   |    |           |   |  -|     | #
#  |    |                   |   |  --|   |   |    ---------   |   |   -|    | #
#  |    |                   |   -----|   |   |            |   |   |    -|   | #
#  ------                   --------------   --------------   -----     ----- #
#                                                                             #
# --------------------------------------------------------------------------- #

# --------------------------------------------------------------------------- #
# OVERVIEW                                                                    #
# --------------------------------------------------------------------------- #

Packetgen uses MoonGen to generate a bursty traffic patten at high packet rates.

The traffic pattern is generated using the following algorithm:

  a) The stream number is set to 0.
  b) The stream base is calculated by multiplying the stream number with the 
     MAC and IP stride.
  c) The burst number is set to 0.
  d) The flow number is set to 0.
  e) A packet is generated with the destination IP and MAC set to "stream 
     base" + "flow number".
  f) The flow number is increased, if it is less than the number of flows per 
     stream, loop back to (e), else continue to (g).
  g) The burst number is increased, if it is less than the number of bursts 
     per stream, loop back to (d), else continue to (h).
  h) The stream base is incremented, if it is less than the number of streams,
     loop back to (a).

The traffic pattern has the following properties:

  -) All packets generated will share the same source IP, source MAC and size 
     profile (fixed size of IMIX, see below).
  -) The destination IP and MAC are selected sequentially as per the above
     pattern.
  -) The sets of streams are separated by the MAC and IP stride, and each
     stream is repeated in bursts. 
  -) The destination IP and MAC increase in lock-step.
  -) Packets size can be fixed (specified when running), or selected from a 
     7:4:1 IMIX profile with packet sizes of 1514, 570, or 64, respectively.

# --------------------------------------------------------------------------- #
# RUNNING                                                                     #
# --------------------------------------------------------------------------- #

From the packetgen directory (MOONGEN_ROOT/examples/packetgen), packetgen can 
be run as follows:

  path/to/MoonGen packetgen.lua [packetgen options]

Or from another directory, packetgen can be run as follows:

  path/to/MoonGen /path/to/packetgen.lua [packetgen options]

Packetgen can be configured entirely from the command line. The options for
configuration are detailed in the configuration section below.

NOTE: To allow MoonGen to run from any directory, you should set the LUA_PATH
      as:

        LUA_PATH=$MOONGEN_ROOT/lua/include/?.lua;\
                 $MOONGEN_ROOT/lua/include/lib/Serpent/init.lua

# DPDK CONF                                                                   #
# --------------------------------------------------------------------------- #

MoonGen looks in the local directory first for a configuration file specifying 
the parameters to use for EAL arguments for DPDK. If MoonGen doees not
recognise any devices, then use:

  MOONGEN_ROOT/deps/dpdk/tools/dpdk_nic_bind.py --status

To get the PCI ID's of the devices which should be used. To get MoonGen to use
the devices, add the PCI ID's to dpdk-conf.lua in:

   MOONGEN_ROOT/examples/packetgen

For example, if dpdk_nic_bind.py returns:

Network devices using DPDK-compatible driver
============================================
0000:03:08.0 'Device 6003' drv=nfp_uio unused=vfio-pci
0000:03:08.1 'Device 6003' drv=nfp_uio unused=vfio-pci

...

Then to make sure that MoonGen can use the two devices above, add:

pciwhite = { "0000:03:08.0", "0000:03:08.1" },

to the dpdk-conf.lua file.

# --------------------------------------------------------------------------- #
# CONFIGURATION                                                               #
# --------------------------------------------------------------------------- #

The described command line options below can be used to configure packetgen.

The explanations take the following format:
  
  -) A | B arg

      : DESCRIPTION
      : arg : ARG DESCRIPTION
      - (DEFAULT)
      * NOTE

where:
  A, B        : Command line option which can be used.
  arg         : Argument for option A or B.
  DESCRIPTION : Description of command line argument.
  DEFAULT     : The default used when this option is not given.
  NOTE        : Special note about specific command line option.


  -) --txd | -A DESCRIPTORS

      : Specifies the number of descriptors to use for TX.
      - (default 1024)

  -) --rxd | -B DESCRIPTORS

      : Specifies the number of descriptors to use for RX.
      - (default 1024)

  -) --dst-vary | -D MAC_VARY,IP_VARY,PORT_VARY

      : Specifies the variation for the destination parameters.
      : MAC_VARY  : Vary destination mac (format a:b:c:d:e:f).
      : IP_VARY   : Vary destination ip (format A.B.C.D).
      : PORT_VARY : Vary destination port (format (a number)).
      * NOTE      : This must be a comma separated list without spaces, eg:
                    aa:00:cd:ef:ff:44,0.0.0.1,2

  -) --rx-ports-mirror-rx|-M VALUE 

        : Specifies if the rx ports must mirror the tx ports.
        : VALUE : If the ports for RX mirror the ports used for TX.
        - (default 0 = false, option 1 = true)
        * NOTE  : If true, and -c 4 -p 0x3 --rx-ports-mirror-tx are
                  the parameters, ports 0, 1 will be used for both
                  RX and TX (they mirror each other), if they aren't
                  set to mirror (default) then the RX ports are allocated 
                  after the TX ports (there is no overlap)

  -) --rx-timeout|-RT TIMEOUT_MS
        
        : Specifies the maximum amount of time each iteration can try to 
          receive for before moving to the next iteration. This prevents 
          ports which have nothing to receive from stalling the application,
        : TIMEOUT_MS : The time in milliseconds to try and receive for on each 
                       iteration.

  -) --src-vary | -S MAC_VARY,IP_VARY,PORT_VARY

      : Specifies the variation for the source parameters.
      : MAC_VARY  : Vary source mac (format a:b:c:d:e:f).
      : IP_VARY   : Vary source ip (format A.B.C.D).
      : PORT_VARY : Vary source port (format (a number)).
      * NOTE      : This must be a comma separated list without spaces, eg:
                    aa:00:cd:ef:ff:44,0.0.0.1,2

  -) --stats-period | -T PERIOD

      : Specifies the period in seconds to refresh the stats.
      - (default 1, 0 = disable)
      * NOTE : The stats for each core are iterated over, and the period of 
               the iteration is PERIOD seconds, following by a delay of 
               PERIOD seconds before restarting the display iteration. e.g
               For 2 cores, with the default period of 1 second, the display
               would:
                  - display first core stats
                  - display second core stats (1s later)
                  - wait 1s, display first core stas again
  
  -) --param-display | -a TIME 

      : Specifies the number of seconds to display the final packetgen params
        after all passed command line options have been set.
      - (default 3 seconds)

  -) --cores | -c CORES

      : Specifies the number of cores to use.
      - (default 1 core)
      * NOTE  : The max number of cores supported is currently 16. This is 
                because MoonGen only allows 15 slaves to be launched, otherwise
                it terminates.

  -) --tx-queues | -d TX_QUEUES

      : Specifies the total number of tx queues to use.
      - (defualt 1)
      * NOTE : All ports in the portmask are allocated as for TX until the
               total number of tx queues has been reached.

  -) --timeout | -e TIME

        : Specifies the amount of time (in seconds) to run for before stopping.
        - (default = 0, is to run indefinitely)

  -) --iterations | -f ITERS

        : Specifies the number of TX/RX iterations to run for.
        - (default = 0, is to run indefinitely)

  -) --mac-stride | -g MAC_STRIDE 

      : Specifies the mac stride between streams.
      : MAC_STRIDE : The format is a:b:c:d:e:f.

  -) --help | -h 

      : Prints the help for packetgen.

  -) --streams | -i STREAMS 

      : Specifies the number of streams to generate.
      - (default 1)

  -) --bursts-per-stream | -j NUM_BURSTS

      : Specifies the number of bursts to send for each stream.
      - (default 1)

  -) --ip-stride | -k IP_STRIDE

      : Specifies the IP stride between the streams.
      : IP_STRIDE : The format is A.B.C.D.

  -) --src-port | -m SRC_PORT 

      : Specifies the base src UDP port.

  -) --dst-port | -n DST_PORT

      : Specifies the base dst UDP port.

  -) --port-stride | -o PORT_STRIDE 

      : Specifies the port stride between streams.

  -) --portmask | -p PORTMASK

      : Specifies the hexadecimal mask of which ports to use.
      - (default 1)

  -) --rx-portmask | -rxp RX_PORTMASK

      : Specifies the mask of the ports to use for RX.
      - (default 0, --portmask is the default use case)
      * NOTE: If this is specified, then -txp must also be used to provide 
              the portmask for TX. If no ports should be used for TX then 
              use -txp 0.

  -) --tx-portmask | -txp TX_PORTMASK

      : Specifies the mask of the ports to use for TX.
      - (default 0, --portmask is the default use case)
      * NOTE : If this is specified, then -rxp must also be used to provide
               the portmask for RX. If no ports should be used for RX then use
               -rxp 0

  -) --queues-per-core | -q QUEUES

      : Specifies the number of queues (ports) which can be used per core.
      - (default 1 -- the default is for each core to have an rx and tx queue.)

  -) --pps | -r RATE 

      : Specifies the desired packet rate (per second) to try and achieve.
      - (default 0)
      * NOTE : 0 turns off the rate functionality and allows the maximum 
               possible number of packets to be generated.

  -) --rx-burst | -R RX_BURST_SIZE 

      : Specifies the size of the RX burst.
      - (default 32)

  -) --tx-burst | -t TX_BURST_SIZE 

      : Specifies the size of the TX burst.
      - (default 32)

  -) --src-mac | -w SRC_MAC

      : Specifies the base source mac address.
      : SRC_MAC : The format is a:b:c:d:e:f

  -) --dst-mac | -x DST_MAC

      : Specifies the base destination MAC address.
      : DST_MAC : The format is a:b:c:d:e:f

  -) --flows-per-stream | -y NUM_FLOWS

      : Specifies the number of flows per stream.
      - (default 2047)

  -) --pkt-size | -z PKT_SIZE

      : Specifies the size of the packets in bytes.
      - (default 64, 0 = IMIX)

# --------------------------------------------------------------------------- #
# NOTES AND RECOMMENDATIONS                                                   #
# --------------------------------------------------------------------------- #

1) MoonGen uses a wrapper around DPDK's mempool to create mempools from which
   packets can be allocated and modified. These mempools are limited in size to
   2047 packets. 

   Packetgen uses a mempool per stream to allocate each of the uniques flows for
   the stream. If the number of flows per stream is greater than 2047, then 2
   mempools need to be created for each stream, which must then be iterated
   over when sending th stream, which results in a performance drop.

   This should be kept in mind when trying to achieve maximum performance.

2) As per the mempool comment in point 1, it is thus preferable to increase the
   number of streams (--streams) rather than the number of flows per stream
   (--flows-per-stream), when trying to get maximum performance, as increasing
   the number of streams does not result in a performance reduction.

3) Packetgen allocates and modifies ALL of the unique flows before the main loop
   which does the sending, so that there is no dynamic allocation of memory to
   reduce the overall performance. The result of this is that the upfront
   memory requirement is large, and trying to allocate too many packets (total
   packets = flows-per-stream * streams) will result in a memory allocation
   error.

   During testing 160 streams with 2047 flows per stream was achieved (+-
   300000 total unique flows)

4) Increasing the number of bursts per stream does not increases the memory usage
   since the burst is a repetition of a stream, and all flows for the stream
   are pre-allocated as mentioned above.

5) Packetgen allocated all available ports to TX until the number of allocated
   ports for TX reaches the total number of TX queues specified by the command
   line option --tx-queues (1 by default). See the examples section for more
   explanation on how to configure packetgen for different settings.
 
# --------------------------------------------------------------------------- #
# EXAMPLES                                                                    #
# --------------------------------------------------------------------------- #

# PORTMASK SPECIFICATION AND CORES                                            #
# --------------------------------------------------------------------------- #

There are two ways that the ports to used can be specified. Either a single
portmask can be used for both RX and TX, or separate portmasks for RX and TX
can be used.

# INDIVIDUAL PORTMASKS:

If individual portmasks are used, then both RX and TX portmasks must be
specified, otherwise packetgen will return an error. CPU cores are first
allocated to the TX ports, and then to the RX cores. If not enough cores are
specified for all the ports (sum of RX and TX enabled cores), then packetgen
will not used the ports which do not have a core to run on.

The following command:

  /path/to/MoonGen packetgen.lua -c 4 -txp 0x3 -rxp 0xc 

will use cores 0, 1 and ports 0, 1 for TX and cores 2, 3 and ports 2, 3 for RX,
which is the following visual representation:

  -------------    -------------    -------------     -------------
  | Core 0    |    | Core 1    |    | Core 2    |     | Core 3    |
  -------------    -------------    -------------     -------------
  | Port 0 TX |    | Port 1 TX |    | Port 2 RX |     | Port 3 RX |
  -------------    -------------    -------------     -------------

# SINGLE PORTMASK:

A single portmask can also be used. The default behaviour in this case is to
first allocate cores and ports for TX until the number of queues specified by
--tx-queues (default 1) is reached, and then to allocate the remainder of the
cores and ports to RX.

The following command:

  /path/to/MoonGen packegen.lua -c 4 -p 0xf

will use core 0 and port 0 to TX, and cores 1, 2, 3 and ports 1, 2, 3 for RX,
which is the following visual representation:

  -------------    -------------    -------------     -------------
  | Core 0    |    | Core 1    |    | Core 2    |     | Core 3    |
  -------------    -------------    -------------     -------------
  | Port 0 TX |    | Port 1 RX |    | Port 2 RX |     | Port 3 RX |
  -------------    -------------    -------------     -------------

When using this format for specifying the portmaks, the --tx-queues parameter 
can be used to specify the number of ports which are allocated for TX.

# BASIC TX BENCHMARKING                                                       #
# --------------------------------------------------------------------------- #

The most basic use case for Packetgen is to simply use a single core to generate
as many packets as possible, which can be done as follows:

  /path/to/MoonGen packetgen.lua -c 1 -p 0x1

This is the default running mode, so is the same as:

  /path/to/MoonGen packetgen.lua 

This will use a single core (-c 1) and use a single (the first available) port
(-p 0x1) with the default parameters. This looks like:

   -------------------
   |      CORE X     |
   -------------------
   |  PORT Y  |  TX  |
   -------------------
                 ---
                  |
                  -------> Generated packets

When running using this configuration the following output shown be shown 
in the terminal:

+------ Statistics for core   1, port   0 ----------------------+
| Packets sent               :                          5447067 |
| Packet send rate           :                        908362.00 |
| Packets received           :                                0 |
| Packet receive rate        :                             0.00 |
| Bytes sent                 :                        348612288 |
| Byte send rate             :                      58135168.12 |
| Bytes received             :                                0 |
| Byte receive rate          :                             0.00 |
| Packets dropped on send    :                                0 |
| Packets dropped on receive :                                0 |
| TX packets short           :                                0 |
| RX mean latency            :                     0.0000000000 |
| RX mean2 latency           :                     0.0000000000 |
+---------------------------------------------------------------+

The above statistics output will update until packetgen is terminated.

# PARAMETER DISPLAY                                                           #
# --------------------------------------------------------------------------- #

Before generating and sending the packets, packetgen displays the parameters
which have been set after the command line options have been parsed. The
default time for which the parameters are displayed is 3 seconds, which can be
changed with the --param-display or -a options.

To run packetgen to only generate and send packets, and display the parameters
for 10 seconds, can be done as follows:

  /path/to/MoonGen packetgen.lua -c 1 -p 0x1 --param-display 10

This should display the following information in the terminal for 10 seconds
before showing the stats as above:

+-------- Parameters ---------------------------------+
| Cores              :                              1 |
| TX queues per core :                              1 |
| RX queues per core :                              1 |
| Portmask           :                              1 |
| Flows per stream   :                           2047 |
| Number of streams  :                              1 |
| Bursts per stream  :                              1 |
| TX burst size      :                             32 |
| RX burst size      :                             32 |
| TX delta           :                              0 |
| Total flows        :                           2047 |
| Packet size        :                             64 |
| Using Imix size    :                          false |
| Timer period       :                              1 |
| ETH src base       :              00:0d:30:59:69:55 |
| ETH src vary       :              00:00:00:00:00:00 |
| ETH dst base       :              54:52:de:ad:be:ef |
| ETH dst vary       :              00:00:00:00:00:01 |
| ETH stride         :              00:00:00:00:00:00 |
| IP src base        :                  192.168.50.10 |
| IP src vary        :                        0.0.0.0 |
| IP dst base        :                  192.168.60.10 |
| IP dst vary        :                        0.0.0.1 |
| IP stride          :                        0.0.0.0 |
| PORT src base      :                           4096 |
| PORT src vary      :                              1 |
| PORT dst base      :                           2048 |
| PORT dst vary      :                              0 |
| PORT stride        :                           2047 |
| No RX descriptors  :                           1024 |
| No TX descriptors  :                           1024 |
| No ports           :                              2 |
| Param display time :                             10 |
+-----------------------------------------------------+

# BASIC TX AND RX BENCHMARKING                                                #
# --------------------------------------------------------------------------- #

To do RX benchmarking in addition to the default TX benchmarking, another port
and core needs to be available. Packetgen uses a separate core for each port,
thus there should be as many cores available as ports being used.

To send the packets out one port and receive them on another can be done as
follows:

  /path/to/MoonGen packetgen.lua -c 2 -p 0x3

Where (-p 0x3) tells packetgen to use the first two available ports.

This looks like the following configuration:

    -------------------              -------------------
    |     CORE A      |              |     CORE B      |
    -------------------              -------------------
    |   PORT 0 |  TX  |              |   PORT 1 |  RX  | 
    -------------------              -------------------
                  ---                               ^
                   |                                |
                   ----------------------------------
                            generated packets

NOTE: This assumes that PORT 0 and PORT 1 have been configured such that
      there is a link between them.

# MULTICORE TX                                                                #
# --------------------------------------------------------------------------- #

Packetgen allocates all ports (and cores) to TX until the number of ports
allocated for TX is equal to the total number of allowed TX ports (this is
specified with the --tx-queues or -d command line arguments, and defaults to
1). Thus to using two cores for transmission (note that each core will
pre-generate the packets, so this could result in significantly increased
memory usage) can be done as follows:

  /path/to/MoonGen packetgen.lua -c 2 -p 0x3 --tx-queues 2

Which tells Packetgen to use the first to available cores and ports for TX. This
looks like the following configuration:

    -------------------              -------------------
    |     CORE A      |              |     CORE B      |
    -------------------              -------------------
    |   PORT 0 |  TX  |              |   PORT 1 |  TX  | 
    -------------------              -------------------
                  ---                              ---
                   |                                |
                   ----> generated packets          ----> generated packets
                      
The stats output will cycle through the cores printing the stats for each of
them, so the following output should be seen in the terminal for the above
configuration:

+------ Statistics for core   1, port   0 ----------------------+
| Packets sent               :                          1725621 |
| Packet send rate           :                        576961.07 |
| Packets received           :                                0 |
| Packet receive rate        :                             0.00 |
| Bytes sent                 :                        110439744 |
| Byte send rate             :                      36925508.65 |
| Bytes received             :                                0 |
| Byte receive rate          :                             0.00 |
| Packets dropped on send    :                                0 |
| Packets dropped on receive :                                0 |
| TX packets short           :                                0 |
| RX mean latency            :                     0.0000000000 |
| RX mean2 latency           :                     0.0000000000 |
+---------------------------------------------------------------+

+------ Statistics for core   2, port   1 ----------------------+
| Packets sent               :                           573160 |
| Packet send rate           :                        571886.94 |
| Packets received           :                                0 |
| Packet receive rate        :                             0.00 |
| Bytes sent                 :                         36682240 |
| Byte send rate             :                      36600764.02 |
| Bytes received             :                                0 |
| Byte receive rate          :                             0.00 |
| Packets dropped on send    :                                0 |
| Packets dropped on receive :                                0 |
| TX packets short           :                                0 |
| RX mean latency            :                     0.0000000000 |
| RX mean2 latency           :                     0.0000000000 |
+---------------------------------------------------------------+

# RATE CONTROL                                                                #
# --------------------------------------------------------------------------- #

Packetgen allows the desired rate to be specified with the (--pps | -r) command
line options, which will limit the packet TX rate to the number of packets
specified, per second. The following command:

  /path/to/MoonGen packetgen.lua --pps 1000000

# STATS DISPLAY CONTROL AND RUNTIME                                           #
# --------------------------------------------------------------------------- #

The amount of time packetgen runs for can be controlled by specifying a total
number of iterations to run for, or a total amount of time to run for, with the
--iterations and --timeout arguments, respectively.

The stats display can be controlled with the --stats-period argument. To turn
of the constant stats display, and to rather have the stats printed at the end
of the run (when either of --iterations or --timeout arguments are provided)
use --stats-period 0.

The following example will run packetgen for 100000 iterations, and then 
display the stats for that period displayed once at the end:

  /path/to/MoonGen packetgen.lua -c 1 -p 1 --stats-period 0 --iterations 100000

The following example will run packetgen for 10 seconds, and then display the
stats for that period once at the end:

  /path/to/MoonGen packetgen.lua -c 1 -p 1 --stats-period 0 --timeout 10

If both the --iterations and --timeout arguments are given, then whichever
action happens first will be the cause of the application terminating.

# PORT SOURCE AND SINK                                                        #
# --------------------------------------------------------------------------- #

To configure a port to both source and sink, the --rx-ports-mirror-tx option is
provided. If the flag is set, then the RX port allocation begins at the start
of the portmask when allocating ports for RX, rather than continuing from the
last allocated TX port, if the option is set to false, which is the default.

For example, to use 2 ports, where both must source and sink, specify the
following parameters to packetgen:

  /path/to/MoonGen packetgen.lua -c 4 -p 0x3 --tx-queues 2 \
    --rx-ports-mirror-tx 1

Which will have the following configuration:

  -------------    -------------    -------------     -------------
  | Core 0    |    | Core 1    |    | Core 2    |     | Core 3    |
  -------------    -------------    -------------     -------------
  | Port 0 TX |    | Port 1 TX |    | Port 0 RX |     | Port 1 RX |
  -------------    -------------    -------------     -------------

NOTE: The use of --tx-queues to control the number of queus which must TX.

If the command did not have the --rx-ports-mirror-tx parameter, as in:

  /path/to/MoonGen packetgen.lua -c 4 -p 0x3 --tx-queues 2 

The configuration would look like:

  -------------    ------------- 
  | Core 0    |    | Core 1    |   
  -------------    -------------   
  | Port 0 TX |    | Port 1 TX |    
  -------------    ------------- 

Because only 2 ports are specified, and only 2 are allocated and both are used
for RX. 

The following command, to specify 4 ports:

   /path/to/MoonGen packetgen.lua -c 4 -p 0x7 --tx-queues 2  

Would result in the following configuration:

  -------------    -------------    -------------     -------------
  | Core 0    |    | Core 1    |    | Core 2    |     | Core 3    |
  -------------    -------------    -------------     -------------
  | Port 0 TX |    | Port 1 TX |    | Port 3 RX |     | Port 4 RX |
  -------------    -------------    -------------     -------------

Because there are now 4 ports available, and ports are allocated so long as
the number of specied cores has not been reached, and there is a valid port in
the portmask.

NOTE: Please see the first first example in this section for how to use the
      -rxp and -txp arguments, which make this functionality simpler to
      achieve.
