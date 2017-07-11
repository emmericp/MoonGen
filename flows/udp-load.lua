Flow{"udp-simple", Packet.Udp{
	ip4Src = ip"10.0.0.10",
	ip4Dst = ip"10.1.0.10",
	udpSrc = 1234,
	udpDst = 319,
	pktLength = 60
	}
}

Flow{"udp-load", Packet.Udp{
		--eth_dst = arp("10.1.0.10"), -- TODO figure out ARP
		ip4Src = list{
				ip"10.0.0.10", ip"10.0.0.11",
				ip"10.0.0.20", ip"10.0.0.21"
		}, -- NOTE automatic conversion ?
		udpSrc = range(1234, 1245),
	},
	parent = "udp-simple"
}
