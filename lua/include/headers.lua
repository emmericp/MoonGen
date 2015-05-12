local ffi = require "ffi"

-- structs
ffi.cdef[[
	// TODO: vlan support (which can be offloaded to the NIC to simplify scripts)
	
	union payload_t {
		uint8_t	uint8[0];
		uint16_t uint16[0];
		uint32_t uint32[0];
		uint64_t uint64[0];
	};

	//  -----------------------------------------------------
	//	---- Address structs
	//  -----------------------------------------------------

	struct __attribute__ ((__packed__)) mac_address {
		uint8_t		uint8[6];
	};

	union ip4_address {
		uint8_t		uint8[4];
		uint32_t	uint32;
	};

	union ip6_address {
		uint8_t 	uint8[16];
		uint32_t	uint32[4];
		uint64_t	uint64[2];
	};
	

	// -----------------------------------------------------
	// ---- Header structs
	// -----------------------------------------------------

	struct __attribute__((__packed__)) ethernet_header {
		struct mac_address	dst;
		struct mac_address	src;
		uint16_t		type;
	};

	struct __attribute__((__packed__)) arp_header {
		uint16_t	hrd;
		uint16_t	pro;
		uint8_t		hln;
		uint8_t		pln;
		uint16_t	op;
		struct mac_address	sha;
		union ip4_address	spa;
		struct mac_address	tha;
		union ip4_address	tpa;
	};
	
	struct __attribute__((__packed__)) ptp_header {
		uint8_t 	messageType;
		uint8_t		versionPTP;
		uint16_t	len;
		uint8_t		domain;
		uint8_t		reserved;
		uint16_t	flags;
		uint32_t	correction[2];
		uint32_t	reserved2;
		uint8_t		oui[3];
		uint8_t		uuid[5];
		uint16_t	ptpNodePort;
		uint16_t	sequenceId;
		uint8_t		control;
		uint8_t		logMessageInterval;
	};

	struct __attribute__((__packed__)) ip4_header {
		uint8_t			verihl;
		uint8_t			tos;
		uint16_t		len;
		uint16_t		id;
		uint16_t		frag;
		uint8_t			ttl;
		uint8_t			protocol;
		uint16_t		cs;
		union ip4_address	src;
		union ip4_address	dst;
	 };

	struct __attribute__((__packed__)) ip6_header {
		uint32_t 		vtf;
		uint16_t  		len;
		uint8_t   		nextHeader;
		uint8_t   		ttl;
		union ip6_address 	src;
		union ip6_address	dst;
	};

	struct __attribute__((__packed__)) icmp_header {
		uint8_t			type;
		uint8_t			code;
		uint16_t		cs;
		union payload_t	body;
	};

	struct __attribute__((__packed__)) udp_header {
		uint16_t	src;
		uint16_t	dst;
		uint16_t	len;
		uint16_t	cs;
	};

	struct __attribute__((__packed__)) tcp_header {
		uint16_t	src;
		uint16_t	dst;
		uint32_t	seq;
		uint32_t	ack;
		uint8_t		offset;
		uint8_t		flags;
		uint16_t	window;
		uint16_t	cs;
		uint16_t	urg;
		uint32_t	options[];
	};
]]

return ffi.C
