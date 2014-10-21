local ffi = require "ffi"

-- structs
ffi.cdef[[
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
	};
]]

return ffi.C
