#!/usr/bin/env python
from scapy.all import *
import sys
pcap_fn = "example.com.pcap"
eaddr = '00:00:00:00:00'

if len(sys.argv) < 2:
	print "Usage: %s pcap_file" % sys.argv[0]
	print "Explanation: Fuzz packets in pcap file"
else:
	pcap_fn = sys.argv[1]	

# Read from pcap
pkts = rdpcap(pcap_fn)

# Fuzz
for i in range(0, len(pkts)):
	p = pkts[i]
	ip = p[IP]
	eth = p[Ether]
	pkts[i] = Ether(dst=eth.dst,src=eth.src)/IP(dst=ip.dst,src=ip.src)/UDP(dport=p.dport)/fuzz(DNS(qd=DNSQR()))

# Dump to pcap
wrpcap(pcap_fn, pkts)

