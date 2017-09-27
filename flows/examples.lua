-- some flows from MoonGen/examples

Flow{"load-latency", Packet.Udp{
		ethSrc = txQueue(),
		ethDst = arp("10.1.0.10"),
		ip4Src = range(ip"10.0.0.10", ip"10.0.0.14"),
		ip4Dst = ip"10.1.0.10",
		udpSrc = 1234,
		udpDst = 319,
		pktLength = 60
	},
	timestamp = true
}

Flow{"quality-of-service", Packet.Udp{
		ethSrc = txQueue(),
		ethDst = mac"10:11:12:13:14:15",
		ip4Src = range(ip"192.168.0.1", ip"192.168.0.255"),
		ip4Dst = ip"10.0.0.1",
		udpSrc = 1234,
		pktLength = 124
	},
	timestamp = true
}

Flow{"qos-foreground", Packet.Udp{
		udpDst = 42
	},
	parent = "quality-of-service",
	rate = 1000
}
Flow{"qos-background", Packet.Udp{
		udpDst = 43
	},
	parent = "quality-of-service",
	rate = 4000
}
