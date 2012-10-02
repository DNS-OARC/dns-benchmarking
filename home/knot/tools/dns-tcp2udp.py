#!/usr/bin/env python
import socket
import struct
import signal
import sys

ip = '127.0.0.1'
sport = 55555
dport = 53531
bufsize = 65535

if len(sys.argv) > 1:
	a = sys.argv[1].split('-')
	sport = int(a[0])
	dport = int(a[1])

print 'Listening on #%d' % sport
tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind( (ip, sport) )
tcp.listen(1)
run = True

def handler(sig, frame):
	global run
	run = False

signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)

while run:
	try:
		conn, addr = tcp.accept()
		qry = conn.recv(bufsize)
		if not qry:
			conn.close()
			continue
		udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
		udp.sendto(qry[2:], (ip, dport))
		ans, addr = udp.recvfrom(bufsize)
		udp.close()
		conn.send(struct.pack('H', socket.htons(len(ans))) + ans)
		conn.close()
		print '%s TCP %d <--> UDP %d (qry %uB, answer %uB)' % (ip, sport, dport, len(qry)-2, len(ans))
	except:
		break

print 'Closing port #%d' % sport
tcp.close()
sys.exit(0)
