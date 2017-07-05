Flow{"udp-load", Packet.Udp{
    eth_src = nil,
    --eth_dst = arp("10.1.0.10"), -- TODO figure out ARP
    ip4_src = list{
        parseIPAddress("10.0.0.10"), parseIPAddress("10.0.0.11"),
        parseIPAddress("10.0.0.20"), (parseIPAddress("10.0.0.21"))
    }, --TODO patch or automatic conversion
    -- NOTE may also keep current fill() format
    ip4_dst = "10.1.0.10",
    udp_src = range(1234, 1245),
    udp_dst = 319,
    pkt_length = 60
  }
}
