\page packet_api Packet API
\tableofcontents

The DPDK provides one main data struct to work with packets: rte_mbuf. MoonGen provides further wrappers, offering enhanced and easy-to-use functions while maintaining critical performance.

\section rte_mbuf rte_mbuf
TBD: Mainly internal struct. Provides some fields to store meta data. Otherwise the actual packet is only bytes.

\section packet_wrappers Dynamic creation of wrappers for c-structs of different packet types
Lua wrapper for the actual packet data. The data can be casted to different kinds of packets that get created dynamically.

\subsection pw_overview Overview
As working with raw bytes isn't productive, MoonGen provides the ability to cast a 'struct rte_mbuf' to different kinds of packets. 
The hereby used c struct is dynamically created, depending on the used cast function. 
The members of the struct are the different headers of the used packet type (for instance an ethernet header, followed by an IPv4 header, ..., followed by payload). 
The headers themselves are implemented in \ref headers.lua .
The respective lua wrapper module of each header can be found in the proto/ folder. 
These provide the functions on the header and its members. 
The functions on packets are dynamically created so they don't have to be reimplemented for each, only minorly differing packettype. 
They are explained in section \ref pw_packets .

\subsection pw_members Functions on Members
The functions for each member of a protocols header are defined in the respective file in the proto/ subfolder. For each member the following functions are implemented:
- set(value) \n
  Set the member (the bytes of that member) to 'value'. Takes care of correct byte order. If no value is provided a reasonable default value is used instead.

- get() \n
  Returns the value of the member. Refer to the documentation to find out the actual data type of the value (number, cdata, ...).

- getString() \n
  Returns a string representation of that value.

Refer to the filebrowser for a complete list of available functions and their documentation.

\subsection pw_headers Functions on Headers
In addition to the above, the following functions are implemented for the header itself:
- fill(namedArgs, prefix) \n
  Invokes the set function of each member of this header. namedArgs is a table containing the values that should be passed to each separate set() function, identified via the respective named argument prepended with the prefix.
  For instance if the header of a packet (so this packets member) is called 'ip4' and one wants to set the protocol field and version.
\code{.lua}
:fill({ 'ip4Protocol'=13, 'ip4Version'=1 }, 'ip4')
\endcode
  All arguments starting with the prefix 'ip4' will be passed to the respective set() function, all other set() functions are called without parameter, hence the default value is set.
  For the list of available arguments see the respective fill() method.

- get(prefix) \n
  Invokes the get function of each member of this header and returns all of their value as table, using the a table of the same named arguments as above, prepended with the specified prefix.

- getString() \n
  Returns a string that is build by invoking the getString function of each member and concatinating the results. This is mainly used to dump the header. 

Note that the set and get function are slow as they use lua tables. Do not use them in time critical parts of your code. Normally you would only use them to prefill a mempool.

Furthermore, there are two functions for each header that are only used internally.

\subsection pw_packets Functions on Packets

- fill(namedArgs) \n
  Invokes fill() for each header (using the correct prefix) and passes the specified table of named arguments. This function always provides "intelligent" default values for named arguments that are not specified. 
  For instance the etherType of an IP4 packet will always be set to the value of IP4, while for an IP6 packet it will be set to the etherType of IP6 (unless the table contains an entry '&lt;prefix&gt;Type', then this will always be used instead). 

- get() \n
  Invokes get() on each header and returns one resulting table.

- dump(bytes) \n
  Prints a tcpdump-like dump of the packet including full cleartext of the headers. Either dumps the specified number of bytes or estimated from the length of the packet struct.

- setLength(len) \n
  Set the length value of each header (it it has one) depending on the packet length and the position of the header in the packet (basically by accumulating the length of headers before this header).

- calculateChecksums() \n
  Calculate all checksums of all headers (that have a checksum field) in software. Has significant impact on the performance. If possible, use checksum-offloading. <!-- TODO link it-->

- calculateChecksumXYZ() \n
  For each header XYZ of the packet that has a checksum member a function to calculate it in software is provided (e.g. calculateChecksumIcmp). Has significant impact on the performance. If possible, use checksum-offloading.


\section create_packet_wrappers Create new packet types
The function packetCreate() of the packet.lua module can be used to create a new user-defined packet type. The user only has to provide the protocols in the order they should appear in the packet. It then automatically creates the respective c struct, consisting of the names headers. The last member is always payload. Furthermore, it automatcally creates the functions mentioned in \ref pw_packets for this kind of packet. packetCreate() returns the cast function for the created packet type.

Per default, the member of the packet for each protocol will be named after the protocol (protocol: ip4, member: ip4). The member can manually be renamed by specifying the name of the protocol, followed by the name of the member in a list, e.g. { 'ip4', 'innerIP'}.
Available protocols: eth (ethernet), ip4, ip6, udp, tcp, arp, icmp, ptp.

Example:
\code{.lua}
local myPacketType = packetCreate('eth', 'ip4', { 'eth', 'secondEth' })
\endcode
The created c struct will look as follows:
\code{.c}
struct ethernet_header eth;
struct ip4_header ip4;
struct ethernet_header secondEth;
union payload_t payload;
\endcode

\subsection pw_summary Summary
Aside from the existing types of packets (listed in the 'Packets' section of each respective protocol module) a user can at any time define further, custom packets. MoonGen then automatically provides functions to work on the packet, on each header of that packet and on each member of such a header. 

\code{.lua}
buf = buf:getUdpPacket()

buf.udp.src = hton(1234)     -- case 1
buf.udp:setSrcPort(1234)     -- case 2
buf.udp:fill{ udpSrc=1234 }  -- case 3
buf:fill{ udpSrc=1234 }      -- case 4
\endcode

All of the four cases result in the same 16 bits of the data set accordingly. However, there are slight differences:
- case 1: Directly works on the c struct. You have to take care of for instance correct byte order yourself.
- case 2: Using the utility functions for members. This method is the recommended one when setting members during the actual 'runtime' of MoonGen. It takes care of correct types and byte order while providing the same speed.
- case 3 and 4: Using a table of named arguments to set multiple/all members of a/all header(s). This method is considerably slower than case 2. The advantage is you can set members to the values you specify and all other members to default values, fitting for the current packet type. This method is therefore recommended when prefilling mempools.
