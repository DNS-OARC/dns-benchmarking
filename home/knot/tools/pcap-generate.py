#!/usr/bin/env python
import sys, getopt
from scapy.all import *
domain = "example.com"
target = "127.0.0.1"
target_port = 53
num_packets = 100
eaddr = '00:00:00:00:00'

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
known = [ "www", "www1" , "www2", "ns", "ns1" , "ns2" ,"dns" , "dns1", "dns2", "dns3", "pop", "mail", "smtp" , 
	"pop3",  "test", "dev" , "ads", "adserver", "adsl", "agent", "channel", "dmz", "sz" , "client", "imap" ,
	"http" , "https", "ftp", "ftpserver", "tftp", "ntp" , "ids" , "ips" , "snort" , "imail" , "pops" , 
        "imaps" , "irc" , "linux" , "windows", "log" , "install", "blog" , "host", "printer", "public" , "sql",
        "mysql", "router" , "cisco" , "switch", "telnet", "voip", "webmin" , "ssh", "delevlop" , "pub" , "root" ,
        "user", "xml", "ww" , "telnet", "extern", "intranet" , "extranet", "testing" , "default", "gateway" ,
        "radius" , "noc" , "mobile", "customer" , "chat" , "siprouter" , "sip" , "nms" , "noc", "office" , 
        "voice" , "support" , "spare" , "owa" , "exchange" ]

# Create list of random names
to_generate = num_packets - len(known)
for i in range (0, to_generate):
	n = RandString(RandNum(1,10), "abcdefghijklmnopqrstuvwxyz0123456789")
	known.append(n)

# Create list of packets
pkts = []
for n in known:
	qn = n + "." + domain
	qr = Ether(dst=eaddr,src=eaddr)/IP(dst=target)/UDP(sport=RandShort(),dport=target_port)/DNS(id=RandShort(),qdcount=1,qd=DNSQR(qname=qn))
	pkts.append(qr)

# Dump to pcap
pcap_out = domain + '.pcap'
wrpcap(pcap_out,  pkts)
