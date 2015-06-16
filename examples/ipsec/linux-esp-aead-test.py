#!/usr/bin/env python

import socket

UDP_IP = "192.168.1.2" #my ip
UDP_PORT = 14 #dst port

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

while True:
    data, addr = sock.recvfrom(1024) # buffer size is 1024 bytes
    print "received message:", data.encode('hex')
