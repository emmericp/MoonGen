Flow{"udp-load", Packet.Udp{
		ethSrc = nil,
		--eth_dst = arp("10.1.0.10"), -- TODO figure out ARP
		ip4Src = list{
				ip"10.0.0.10", ip"10.0.0.11",
				ip"10.0.0.20", ip"10.0.0.21"
		}, --TODO patch or automatic conversion
		-- NOTE may also keep current fill() format
		ip4Dst = ip"10.1.0.10",
		udpSrc = range(1234, 1245),
		udpDst = 319,
		pktLength = 60
	}
}
