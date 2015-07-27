#!/bin/bash

echo 1 > /proc/sys/net/ipv4/ip_forward #enable packet forwarding
OUT_IF="eth7" #connected to narva:1 / dumpSlave
IN_IF="eth6" #connected to narva:0 / loadSlave
ip link set up dev $OUT_IF #enable interface
ip addr add 1.1.1.1/24 dev $OUT_IF
ip link set up dev $IN_IF
ip addr add 10.0.1.254 dev $IN_IF

arp -i $OUT_IF -s 2.2.2.2 90:e2:ba:35:b5:80 #set ARP for klaipeda:0
#arp -i $OUT_IF -d 2.2.2.2 #delete ARP
ip route add 2.2.2.2 dev $OUT_IF
ip route add 10.0.2.0/24 dev $OUT_IF


#ip route add 10.0.1.0/24 dev eth10 src 192.168.1.1

ip xfrm state flush
ip xfrm policy flush

# From Linux (192.168.1.1) to MoonGen (192.168.1.2)
# Security Association
ip xfrm state add src 1.1.1.1 dst 2.2.2.2 proto esp spi 0xdeadbeef mode tunnel aead "rfc4106(gcm(aes))" 0x77777777deadbeef77777777DEADBEEFff0000ff 128
#echo "Security Associations:"
#ip xfrm state list

# Security Policy
ip xfrm policy add src 10.0.1.0/24 dst 10.0.2.0/24 dir out tmpl src 1.1.1.1 dst 2.2.2.2 proto esp mode tunnel 
#echo "Security Policies:"
#ip xfrm policy list

