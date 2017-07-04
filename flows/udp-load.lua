Flow{"udp-load", packet.udp{
    eth_src = nil,
    eth_dst = arp("10.1.0.10"),
    ip4_src = "10.0.0.10",
    ip4_dst = "10.1.0.10",
    udp_src = 1234,
    udp_dst = 319,
    pktLength = 60
  }
}
