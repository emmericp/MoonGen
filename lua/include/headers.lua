local ffi = require "ffi"

-- structs
ffi.cdef[[
	struct mac_address {
		uint8_t byte[6];
	};

	struct ethernet_header {
		struct mac_address 	dst;
		struct mac_address 	src;
		uint16_t 		ethertype;
	};

	struct ipv4_address {
		union {
			uint8_t		byte[4];
			uint16_t	word[2];
			uint32_t	addr;
		};
	};

	struct ipv6_address {
		union {
			uint8_t 	byte[16];
			uint16_t	word[8];
		};
	};

	struct ipv4_header {
		 uint8_t	verihl; 		                  /* hardcoded version + ihl!! */ 
		 uint8_t      	tos;                    /* type of service */                   
		 uint16_t     	len;                    /* total length */              
		 uint16_t     	id;                     /* identification */                    
		 uint16_t     	fragOff;                /* fragment offset field */     
		 uint8_t      	ttl;                    /* time to live */                      
		 uint8_t      	protocol;               /* protocol */                  
		 uint16_t     	check;                  /* checksum */       
		 
		 struct ipv4_address	src;
		 struct ipv4_address	dst;
	 };

	 struct ipv6_header {
		uint32_t 	vtf; 			  /* = version(6) + Traffic Class(0) + Flow Label(0); */    
		                 			/* should be 0x6000 0000 on our architecture */           
					                                                                                  
	  uint16_t  len;                                     
		uint8_t   nexthdr;                                        
		uint8_t   ttl;                                       
		                                                               
		struct ipv6_address src;
		struct ipv6_address	dst;
	};

	 struct udp_header {                                                             
		 uint16_t     src;	    /* source port */                               
		 uint16_t     dst;    	/* destination port */                          
		 uint16_t     len;    	/* udp length */                                
		 uint16_t     check; 	  /* udp checksum */                              
	};

	struct __attribute__ ((__packed__)) packet {
		struct ethernet_header  eth_h;
		union __attribute__ ((__packed__)) {
			struct ipv4_header 	ipv4_h;
		//	struct ipv6_header	ipv6_h;
		};
		struct udp_header 	udp_h;
	};
]]

return ffi.C
