Flow{"errors", Packet.udp{},
	test = 1,
	rate = {},
	parent = 1,
	mode = 1,
}

Flow{"errors", Packet.udp{},
	rate = "mb/s",
	parent = "??",
	mode = "??",
}

Flow{"e1", Packet.udp{},
	rate = "1a",
}

Flow{"e2", Packet.udp{},
	rate = "1b/a",
}
