#!/usr/bin/env python
import sys, getopt
from scapy.all import *
domain = "example.com"
target = "192.168.1.10"
ipfrom = '192.168.1.30'
target_port = 53531
num_packets = 100
eaddr = '78:ac:c0:88:94:94'
deaddr = '78:ac:c0:88:94:30'

# Usage
def usage():
	print "%s: [-h] [-d DOMAIN] [-t TARGET] [-p PORT] [-n NUM_PACKETS]" % sys.argv[0]
	print "Parameters:"
	print "\t-h\tHelp."
	print "\t-d DOMAIN\tDomain containing generated names (%s)." % "example.com"
	print "\t-t TARGET\tTarget DNS server (%s)." % "127.0.0.1"
	print "\t-p PORT\tTarget DNS server port (%d)." % 53531
	print "\t-n NUM\tNumber of generated packets (%d)." % 100

# Parse options
try:
	opts, args = getopt.getopt(sys.argv[1:], "hd:t:p:n:", [])
except getopt.GetoptError, err:
	usage()
	sys.exit(1)
if len(args) > 0:
	usage()
	sys.exit(1)
for o, a in opts:
	if o == '-h':
		usage()
		sys.exit(1)
	elif o == '-d':
		domain = a
	elif o == '-t':
		target = a
	elif o == '-p':
		target_port = int(a)
	elif o == '-n':
		num_packets = int(a)
	else:
		usage()
		sys.exit(1)

# Overview
print "domain = %s" % domain
print "target = %s:%d" % (target, target_port)
print "packets = %d" % num_packets

# List of common names according to http://www.packetlevel.ch/html/scapy/scapydns.html
known = open(domain + '.dict')

# Create list of packets
pkts = []
ctr = 0
for line in known:
	line = line.strip().split(' ')	
	qn = line[0]
	qt = line[1]
	qr = Ether(dst=deaddr,src=eaddr)/IP(dst=target,src=ipfrom)/UDP(sport=RandShort(),dport=target_port)/DNS(id=RandShort(),qdcount=1,qd=DNSQR(qname=qn,qtype=qt))
	pkts.append(qr)
	ctr += 1
	if ctr % 10000 == 0:
		print "%d queries written" % ctr

# Dump to pcap
known.close()
pcap_out = domain + '.pcap'
wrpcap(pcap_out,  pkts)
