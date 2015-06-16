#!/bin/bash
ip xfrm state flush
ip xfrm policy flush

# From MoonGen (10.0.0.1) to Linux (192.168.1.1)
# Security Association
ip xfrm state add src 10.0.0.1 dst 192.168.1.1 proto esp spi 0xdeadbeef aead "rfc4106(gcm(aes))" 0x77777777deadbeef77777777DEADBEEFff0000ff 128 mode transport
echo "Security Associations:"
ip xfrm state list

# Security Policy
ip xfrm policy add src 10.0.0.1 dst 192.168.1.1 dir in tmpl src 10.0.0.1 dst 192.168.1.1 proto esp mode transport
echo "Security Policies:"
ip xfrm policy list
