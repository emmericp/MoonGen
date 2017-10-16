Flow{"errors", Packet.Udp{},
	test = 1,
	rate = {},
	parent = 1,
	mode = 1,
}

Flow{"errors", Packet.Udp{},
	rate = "mb/s",
	parent = "??",
	mode = "??",
}

Flow{"e1", Packet.Udp{},
	rate = "1a",
}

Flow{"e2", Packet.Udp{},
	rate = "1b/a",
}

Flow{"valid", Packet.Udp{
	pktLength = 60
}}

Flow{"f1", Packet.Udp{}}
