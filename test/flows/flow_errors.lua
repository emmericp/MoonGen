Flow{"errors", Packet.udp{},
	test = 1,
	rate = {}
}

Flow{"errors", Packet.udp{},
	rate = "mb/s"
}

Flow{"e1", Packet.udp{},
	rate = "1a"
}

Flow{"e2", Packet.udp{},
	rate = "1b/a"
}
