local ffi = require "ffi"

-- structs
ffi.cdef[[
<<<<<<< HEAD
	struct __attribute__ ((__packed__)) mac_address {
		uint8_t byte[6];
	};

	struct __attribute__ ((__packed__)) ethernet_header {
		struct mac_address 	dst;
		struct mac_address 	src;
		uint16_t 		ethertype;
	};

	struct __attribute__ ((__packed__)) ipv4_address {
		union {
			uint8_t		byte[4];
			uint16_t	word[2];
			uint32_t	addr;
		};
	};

	struct __attribute__ ((__packed__)) ipv6_address {
		union {
			uint8_t 	byte[16];
			uint16_t	word[8];
		};
	};

	struct __attribute__ ((__packed__)) ipv4_header {
		uint8_t	verihl; 			/* hardcoded version + ihl!! */ 
		uint8_t      	tos;                    /* type of service */                   
		uint16_t     	len;                    /* total length */              
		uint16_t     	id;                     /* identification */                    
		uint16_t     	fragOff;                /* fragment offset field */     
		uint8_t      	ttl;                    /* time to live */                      
		uint8_t      	protocol;               /* protocol */                  
		uint16_t     	check;                  /* checksum */       
	
		struct ipv4_address	src;		/* source address */
		struct ipv4_address	dst;		/* destination address */
	 };

	struct __attribute__ ((__packed__)) ipv6_header {
		uint32_t 	vtf; 			/* = version(6) + Traffic Class(0) + Flow Label(0); */    
							/* should be 0x6000 0000 on our architecture */           
		uint16_t  	len;			/* payload length */
		uint8_t   	nexthdr;		/* next header */
		uint8_t   	ttl;  			/* time to live */                                 
		                                                               
		struct ipv6_address 	src;		/* source address */
		struct ipv6_address	dst;		/* destination address */
	};

	struct __attribute__ ((__packed__)) udp_header {                                                             
		uint16_t 	src;	    		/* source port */                               
		uint16_t     	dst;    		/* destination port */                          
		uint16_t     	len;    		/* udp length */                                
		uint16_t     	check; 	  		/* udp checksum */                              
	};

	struct __attribute__ ((__packed__)) packet {
		struct ethernet_header  eth_h;
		//union {
		struct ipv4_header 	ipv4_h;
		//	struct ipv6_header	ipv6_h;
		//};
		struct udp_header 	udp_h;
=======
	// TODO: vlan support (which can be offloaded to the NIC to simplify scripts)
	struct __attribute__((__packed__)) ethernet_header {
		uint8_t		dst[6];
		uint8_t		src[6];
		uint16_t	type;
	};

	struct __attribute__((__packed__)) ipv4_address {
		union {
			uint8_t		uint8[4];
			uint32_t	uint32;
		};
	};

	struct __attribute__((__packed__)) ipv6_address {
		union {
			uint8_t 	uint8[16];
			uint32_t	uint32[4];
			uint64_t	uint32[2];
		};
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
		struct ipv4_address	src;
		struct ipv4_address	dst;
	 };

	struct __attribute__((__packed__)) ipv6_header {
		uint32_t 		vtf;
		uint16_t  		len;
		uint8_t   		nextHeader;
		uint8_t   		ttl;
		struct ipv6_address 	src;
		struct ipv6_address	dst;
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
>>>>>>> upstream/master
	};
]]

return ffi.C
