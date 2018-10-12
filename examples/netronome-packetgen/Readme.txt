# --------------------------------------------------------------------------- #
#                                                                             #
#        Copyright (C) 2016 Netronome Systems, Inc. All rights reserved.      #
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

  path/to/MoonGen /path/to/packetgen.lua --dpdk-config=/path/to/dpdk-conf.lua 
      [packetgen options]

Packetgen can be configured entirely from the command line. The options for
configuration are detailed in the configuration section below.

NOTE: To allow MoonGen to run from any directory, you should set the LUA_PATH
      as:
    
        export MOONGEN_ROOT=/path/to/MOONGEN_ROOT
        export LUA_PATH="$MOONGEN_ROOT/lua/include/?.lua;\
                         $MOONGEN_ROOT/lua/include/lib/Serpent/init.lua"

# DPDK CONF                                                                   #
# --------------------------------------------------------------------------- #

MoonGen looks in the local directory first for a configuration file specifying 
the parameters to use for EAL arguments for DPDK. The default provided with 
Netronome's version of MoonGen does not specify any parameters, which tells 
MoonGen to use the defaults. If MoonGen does not recognise any devices, then 
use:

  MOONGEN_ROOT/deps/dpdk/tools/dpdk_nic_bind.py --status

To get the PCI HW addresses of the devices which should be used. To get 
MoonGen to use the devices, add the PCI HW addresses to dpdk-conf.lua in:

   MOONGEN_ROOT/examples/packetgen

For example, if dpdk_nic_bind.py --status returns:

Network devices using DPDK-compatible driver
============================================
0000:03:08.0 'Device 6003' drv=nfp_uio unused=vfio-pci
0000:03:08.1 'Device 6003' drv=nfp_uio unused=vfio-pci

...

Then to make sure that MoonGen can use the two devices above, add:

pciwhite = { "0000:03:08.0", "0000:03:08.1" },

to the dpdk-conf.lua file.

NOTE: MoonGen looks in the directory from which MoonGen is run for the
      dpdk-conf.lua to use for configuration. The dpdk-conf.lua file which 
      comes with MoonGen (in MOONGEN_ROOT/examples/packetgen) provides 
      descriptions of each of the parameters.

The location of the dpdk-conf.lua file can also be given as an argument to
MoonGen. It must be AFTER the script to run, but BEFORE the scripts' arguments.
For example, to use a dpdk-conf.lua file in the home directory:

  path/to/MoonGen /path/to/packegen.lua --dpdk-config=~/dpdk-conf.lua
    [packetgen.lua args]

For this to succeed, the LUA_PATH environment variable must be set as:

    LUA_PATH="$MOONGEN_ROOT/lua/include/?.lua;\
             $MOONGEN_ROOT/lua/include/lib/Serpent/init.lua"
# --------------------------------------------------------------------------- #
# CONFIGURATION                                                               #
# --------------------------------------------------------------------------- #

Packetgen has an option to print out it's help, which specifies the numerous
command line parameters. To view the parameters and the explanations and
examples which go with them, do:

  path/to/MoonGen /path/to/packegen.lua --help

  or

  path/to/MoonGen /path/to/packegen.lua -h

# --------------------------------------------------------------------------- #
# NOTES AND RECOMMENDATIONS                                                   #
# --------------------------------------------------------------------------- #

1) MoonGen uses a wrapper around DPDK's mempool to create mempools from which
   packets can be allocated and modified. These mempools are limited in size to
   2047 packets, so packetgen can generate of 2047 flows per stream. If more 
   variation in the traffic pattern is required, increase the number of 
   streams. 

2) Packetgen allocates and modifies ALL of the unique flows before the main loop
   which does the sending so that there is no dynamic allocation of memory to
   reduce the overall performance. The result of this is that the upfront
   memory requirement is large, and trying to allocate too many packets (total
   packets = flows-per-stream * streams) will result in a memory allocation
   error.

   During testing 160 streams with 2047 flows per stream was achieved (+-
   300000 total unique flows)

3) Increasing the number of bursts per stream does not increases the memory 
   usage since the burst is a repetition of a stream, and all flows for the 
   stream are pre-allocated as mentioned above.

4) Packetgen script does allow for both timestamping and rate control, but they 
   are done in software. Both are suboptimal when done in software as they are 
   exposed to the garbage collector and LUA JIT pauses. The rate control is 
   implemented by sending outgoing packets to the queue (via DPDK) and then 
   waiting until enough time has passed before submitting the next batch of 
   packets to the queue. Unfortunately, there is no control over when the 
   packets in the queue are sent out, introducing a small amount of error in 
   some cases. 

# --------------------------------------------------------------------------- #
# EXAMPLES                                                                    #
# --------------------------------------------------------------------------- #

# BASIC TX BENCHMARKING                                                       #
# --------------------------------------------------------------------------- #

The most basic use case for Packetgen is to simply use a single core to generate
as many packets as possible, which can be done as follows:

  /path/to/MoonGen packetgen.lua -tx 0

This will use a single core and use a single (the first available) tx slave (on
port 0) with the default parameters (printing stats to the console). This 
looks like:

   -------------------
   |      CORE X     |
   -------------------
   |  PORT Y  |  TX  |
   -------------------
                 ---
                  |
                  -------> Generated packets

# PARAMETER DISPLAY                                                           #
# --------------------------------------------------------------------------- #

Before generating and sending the packets, packetgen displays the parameters
which have been set after the command line options have been parsed. The
default time for which the parameters are displayed is 3 seconds, which can be
changed with the --param-display or -pd options.

To run packetgen to only generate and send packets, and display the parameters
for 10 seconds, can be done as follows:

  /path/to/MoonGen packetgen.lua -tx 0 -pd 10


# BASIC TX AND RX BENCHMARKING                                                #
# --------------------------------------------------------------------------- #

To do RX benchmarking in addition to the default TX benchmarking, another slave
must be specified as an rx slave. To create a tx slave to send the packets out 
port 0 and another rx slave to receive them on port 1 can be done as follows:

  /path/to/MoonGen packetgen.lua -tx 0 -rx 1

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

# MULTIPLE SLAVES                                                             #
# --------------------------------------------------------------------------- #

Multiple tx and rx slaves can be specified.

For example, to create 2 slaves for transmission on using ports 0 and 1:

  /path/to/MoonGen packetgen.lua -tx 0 -tx 1

Which looks like the following configuration:

    -------------------              -------------------
    |     CORE A      |              |     CORE B      |
    -------------------              -------------------
    |   PORT 0 |  TX  |              |   PORT 1 |  TX  | 
    -------------------              -------------------
                  ---                              ---
                   |                                |
                   ----> generated packets          ----> generated packets
                      
# RATE CONTROL                                                                #
# --------------------------------------------------------------------------- #

Packetgen allows the desired rate to be specified with the (--pps | -r) command
line options, which will limit the packet TX rate to the number of packets
specified, per second. The following command:

  /path/to/MoonGen packetgen.lua -tx 0 --pps 1000000

will limit the number of generated packet to 1M packets per second.

# STATS OUTPUT                                                                #
# --------------------------------------------------------------------------- #

Packetgen provides a few options for displaying and printing the stats. These
options are specified by the --write-mode or -wm options. 

The duration of the stats for a single slave can be specified by the 
--stats-display or -sd options. The stats for all slaves are iterated over, and
the total iteration time over all the slaves is the value specified to -sd. For
example:

    -tx 0 -rx 1 -sd 1, will print stats at the following intervals:
      
       Time | Port  | Mode  
     -----------------------
       0s   | 0     | TX
       0.5s | 1     | RX
       1.0s | 0     | TX
       1.5s | 1     | RX

  or  

       Time | Port  | Mode  
     -----------------------
       0s   | 1     | RX
       0.5s | 0     | TX
       1.0s | 1     | RX
       1.5s | 0     | TX 

  depending on how the cores were allocated to the tx and rx slaves by MoonGen.

NOTE: If -sd is too small, that it may take longer to send/receive the packets 
      on an iteration than to allocated tiem to display the stats, in which
      case some cores stats may not be printed, and the stats output will not
      be as expected.

  The following options are available for the write mode:

  -wm 0 : No output will be written to file or printed to the console. The
          final stats will be printed once at the end.
  -wm 1 : The stats will be printed for each slave, iteratively as explained
          above.
  -wm 2 : Write all slave stats to a single global file with a prefix specified 
          by --file-prefix or -fp
  -wm 3 : Write each slave's stats to it's own file with the format:
          <prefix>-c<core-num>-p<port-num>, where:
              core-num : Number of the core the slave is executing on    
              port-num : Port the slave is using to RX or TX.


NOTE: If -fp is specified by -wm is not given, then the default is to write to
      a global file (i.e -wm 2)

The following example would write the stats to a file named example.txt:

  /path/to/MoonGen packetgen.lua -tx 0 -rx 1 -fp example 

The following would generate example-c0-p0.txt example-c1-p1.txt, where each
file has the stats for only one slave:

  /path/to/MoonGen packetgen.lua -tx 0 -rx 1 -fp example -wm 3

# RUNTIME CONTROL                                                             #
# --------------------------------------------------------------------------- #

The amount of time packetgen runs for can be controlled by specifying a total
number of iterations to run for, or a total amount of time to run for, with the
(--iterations | -it) and (--timeout | -to) arguments, respectively.

The following example will run packetgen for 100000 iterations, and then 
display the stats for that period displayed once at the end:

  /path/to/MoonGen packetgen.lua -tx 0 --iterations 100000

The following example will run packetgen for 10 seconds, and then display the
stats for that period once at the end:

  /path/to/MoonGen packetgen.lua -tx 0 --timeout 10

If both the --iterations and --timeout arguments are given, then whichever
action happens first will be the cause of the application terminating.

# PORT SOURCE AND SINK                                                        #
# --------------------------------------------------------------------------- #

To configure a port to both source and sink just use the -tx and -rx options
with the same values.

For example, to use 2 ports, where both must source and sink, specify the
following parameters to packetgen:

  /path/to/MoonGen packetgen.lua -tx 0 -rx 0 -tx 1 -rx 1

Which will have the following configuration:

  -------------    -------------    -------------     -------------
  | Core 0    |    | Core 1    |    | Core 2    |     | Core 3    |
  -------------    -------------    -------------     -------------
  | Port 0 TX |    | Port 1 TX |    | Port 0 RX |     | Port 1 RX |
  -------------    -------------    -------------     -------------

# PACKET VARIATION                                                            #
# --------------------------------------------------------------------------- #

The packets generated by packetgen can be configured from the command line.
The ip addresses, mac addresses, and port numbers of the source and destination
can be modified, both per flow and per stream (set of flows).

The following parameters modify the packet properties per flow (each packet in
the flow will vary by the amounts specified by the following parameters):

  | Parameter Option:        | Argument format:    |
  |================================================|
  |--src-mac-vary   or -smv  |  aa:bb:cc:dd:ee:ff  |
  |================================================|
  | --dst-mac-vary  or -dmv  |  aa:bb:cc:dd:ee:ff  |
  |================================================|
  | --src-ip-vary   or -sipv |  0.0.0.1            |
  |================================================|
  | --dst-ip-vary   or -dipv |  0.0.0.1            |
  |================================================|
  | --src-port-vary or -sptv |  1                  |
  |================================================|
  | --dst-port-vary or -dptv |  1                  |
  |================================================|

The following paramters modify the packet properties per stream:

  | Parameter Option:          | Argument format:    |
  |==================================================|
  |--src-mac-stride   or -sms  |  aa:bb:cc:dd:ee:ff  |
  |==================================================|
  | --dst-mac-stride  or -dmv  |  aa:bb:cc:dd:ee:ff  |
  |==================================================|
  | --src-ip-stride   or -sipv |  0.0.0.1            |
  |==================================================|
  | --dst-ip-stride   or -dipv |  0.0.0.1            |
  |==================================================|
  | --src-port-stride or -sptv |  1                  |
  |==================================================|
  | --dst-port-stride or -dptv |  1                  |
  |==================================================|



