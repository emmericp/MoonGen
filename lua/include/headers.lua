------------------------------------------------------------------------
--- @file headers.lua
--- @brief C struct definitions for all protocol headers and respective 
--- additional structs for instance addresses.
--- Please check the source code for more information.
------------------------------------------------------------------------

local ffi = require "ffi"

-- structs
ffi.cdef[[
	
	union payload_t {
		uint8_t	uint8[0];
		uint16_t uint16[0];
		uint32_t uint32[0];
		uint64_t uint64[0];
	};

	//  -----------------------------------------------------
	//	---- Address structs
	//  -----------------------------------------------------

	union __attribute__((__packed__)) mac_address {
		uint8_t		uint8[6];
		uint64_t	uint64[0]; // for efficient reads
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

	union ipsec_iv {
		uint32_t	uint32[2];
	};

	union ipsec_icv {
		uint32_t	uint32[4];
	};
	

	// -----------------------------------------------------
	// ---- Header structs
	// -----------------------------------------------------

	// TODO: there should also be a variant with a VLAN tag
	// note that this isn't necessary for most cases as offloading should be preferred
	struct __attribute__((__packed__)) ethernet_header {
		union mac_address	dst;
		union mac_address	src;
		uint16_t		type;
	};

	struct __attribute__((__packed__)) arp_header {
		uint16_t	hrd;
		uint16_t	pro;
		uint8_t		hln;
		uint8_t		pln;
		uint16_t	op;
		union mac_address	sha;
		union ip4_address	spa;
		union mac_address	tha;
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
	
	struct __attribute__((__packed__)) vxlan_header {
		uint8_t		flags;
		uint8_t		reserved[3];
		uint8_t		vni[3];
		uint8_t		reserved2;
	};

	struct __attribute__((__packed__)) esp_header {
		uint32_t	spi;
		uint32_t	sqn;
		union ipsec_iv	iv;
	};

	struct __attribute__((__packed__)) ah_header {
		uint8_t		nextHeader;
		uint8_t		len;
		uint16_t	reserved;
		uint32_t	spi;
		uint32_t	sqn;
		union ipsec_iv	iv;
		union ipsec_icv	icv;
	};

	// https://www.ietf.org/rfc/rfc1035.txt
	struct __attribute__((__packed__)) dns_header {
		uint16_t	id;
		uint16_t	hdrflags;
		uint16_t	qdcount;
		uint16_t	ancount;
		uint16_t	nscount;
		uint16_t	arcount;
		uint8_t		body[];
	};

	// -----------------------------------------------------
	// ---- https://tools.ietf.org/html/rfc7011
	// ---- IPFIX structures
	// -----------------------------------------------------

	struct __attribute__((__packed__)) ipfix_header {
		uint16_t	version;
		uint16_t	length;
		uint32_t	export_time;
		uint32_t	sequence_number;
		uint32_t	observation_domain_id;
	};

	struct __attribute__((__packed__)) ipfix_set_header {
		uint16_t	set_id;
		uint16_t	length;
	};

	struct __attribute__((__packed__)) ipfix_tmpl_record_header {
		uint16_t	template_id;
		uint16_t	field_count;
	};

	struct __attribute__((__packed__)) ipfix_opts_tmpl_record_header {
		uint16_t	template_id;
		uint16_t	field_count;
		uint16_t	scope_field_count;
	};

	struct __attribute__((__packed__)) ipfix_information_element {
		uint16_t	ie_id;
		uint16_t	length;
	};

	struct __attribute__((__packed__)) ipfix_data_record {
		uint8_t		field_values[?];
	};

	struct __attribute__((__packed__)) ipfix_tmpl_record {
		struct ipfix_tmpl_record_header		template_header;
		struct ipfix_information_element	information_elements[5];
	};

	struct __attribute__((__packed__)) ipfix_opts_tmpl_record {
		struct ipfix_opts_tmpl_record_header	template_header;
		struct ipfix_information_element	information_elements[5];
	};

	struct __attribute__((__packet__)) ipfix_data_set {
		struct ipfix_set_header		set_header;
		uint8_t				field_values[?];
	};

	struct __attribute__((__packet__)) ipfix_tmpl_set {
		struct ipfix_set_header		set_header;
		struct ipfix_tmpl_record	record;
		uint8_t				padding;
	};

	struct __attribute__((__packet__)) ipfix_opts_tmpl_set {
		struct ipfix_set_header		set_header;
		struct ipfix_opts_tmpl_record	record;
		uint8_t				padding;
	};
]]

return ffi.C
