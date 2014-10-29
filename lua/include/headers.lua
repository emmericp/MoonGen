local ffi = require "ffi"

-- structs
ffi.cdef[[
	// TODO: vlan support (which can be offloaded to the NIC to simplify scripts)
	struct __attribute__((__packed__)) ethernet_header {
		uint8_t		dst[6];
		uint8_t		src[6];
		uint16_t	type;
	};

	union ipv4_address {
		uint8_t		uint8[4];
		uint32_t	uint32;
	};

	union ipv6_address {
		uint8_t 	uint8[16];
		uint32_t	uint32[4];
		uint64_t	uint64[2];
	};

	struct __attribute__((__packed__)) ipv4_header {
		uint8_t			verihl;
		uint8_t			tos;
		uint16_t		len;
		uint16_t		id;
		uint16_t		frag;
		uint8_t			ttl;
		uint8_t			protocol;
		uint16_t		cs;
		union ipv4_address	src;
		union ipv4_address	dst;
	 };

	struct __attribute__((__packed__)) ipv6_header {
		uint32_t 		vtf;
		uint16_t  		len;
		uint8_t   		nextHeader;
		uint8_t   		ttl;
		union ipv6_address 	src;
		union ipv6_address	dst;
	};

	struct __attribute__((__packed__)) udp_header {                                                             
		uint16_t 	src;
		uint16_t     	dst;
		uint16_t     	len;
		uint16_t     	cs;
	};

	struct __attribute__((__packed__)) udp_packet {
		struct ethernet_header  eth;
		struct ipv4_header 	ip;
		struct udp_header 	udp;
		uint8_t			payload[];
	};

	struct __attribute__((__packed__)) udp_v6_packet {
		struct ethernet_header  eth;
		struct ipv6_header 	ip;
		struct udp_header 	udp;
		uint8_t			payload[];
	};
]]

return ffi.C
