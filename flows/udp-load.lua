Flow{"udp-load", udp4{
    ethSrc = nil,
    ethDst = arp(), --arp(ip = ip4Dst, timeout = 5)
    ip4Src = "10.0.0.10",
    ip4Dst = "10.1.0.10",
    udpSrc = 1234,
    udpDst = 319,
    pktLength = 60
  }
}
