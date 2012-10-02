#!/usr/bin/env python
'''
Usage: digcmp.py [options] 

Parse dig output to make RRs context-aware and
optionally tag or hide records matching a rule set.

Rule set file syntax:
mask|<string>	regex

e.g:
warning         "[additionals] some.name"

Parameters:
	-r, --rules=file	Path to rule set file.
'''
import subprocess
import fileinput
import getopt
import sys
import re

class State:
	(RR) = 0
	(AXFR_BEGIN, AXFR) = (1, 2)
	(IXFR_BEGIN, IXFR_CHANGESET, IXFR_REMOVE, IXFR_ADD) = (3, 4, 5, 6)

global g_section
global g_state
global g_serial
global g_rules
g_rules = []
g_section = 'global'
g_state = State.RR
g_serial = 0

def print_data(l, prefix = None):
	tag = g_section
	if prefix != None:
		tag += ' ' + prefix
	print '[%s] %s' % (tag, l)

def serial_set(k):
	global g_serial
	g_serial = k

def enter_state(k):
	global g_state
	g_state = k

def enter_section(s):
	global g_section
	g_section = s.lower()

def enter(s, k):
	enter_state(s)
	enter_section(k)

def parse_soa_serial(l):
	m = re.search('in soa [^ ]+ [^ ]+ ([0-9]+)', l)
	if m != None:
		return int(m.group(1))
	return None
	
def parse_meta(l):
	m = re.search('([A-Z]+) (PSEUDOSECTION|SECTION):', l)
	if m != None:
		return enter_section(m.group(1))
	m = re.search('->>HEADER<<- opcode: ([A-Z]+), status: ([A-Z]+)', l)
	if m != None:
		enter_section('header')
		print_data('op: %s' % m.group(1))
		print_data('status: %s' % m.group(2))
		return

def parse_data(l):
	l = re.sub(r'\s+', ' ', l.lower())

	# AXFR
	if   g_state == State.AXFR_BEGIN:
		pass
	elif g_state == State.AXFR:
		pass
	# IXFR
	elif g_state == State.IXFR_BEGIN:
		sn = parse_soa_serial(l)
		if sn != None:
			serial_set(sn)
			enter(State.IXFR_CHANGESET, 'ixfr-soa')
		return # Hide RR
	elif g_state == State.IXFR_CHANGESET:
		sn = parse_soa_serial(l)
		if sn != None:
			enter(State.IXFR_REMOVE, 'ixfr-add sn=%d' % sn)
		pass
	elif g_state == State.IXFR_REMOVE:
		sn = parse_soa_serial(l)
		if sn != None:
			enter(State.IXFR_ADD, 'ixfr-rem sn=%d' %sn)
		pass
	elif g_state == State.IXFR_ADD:
		sn = parse_soa_serial(l)
		if sn != None:
			if sn == g_serial:
				enter(State.IXFR_BEGIN, 'ixfr-soa')
				return # Hide RR
			else:
				enter(State.IXFR_REMOVE, 'ixfr-rem sn=%d' % sn)
		pass
	else:
		pass
	return print_data(l)

def parse_opts(l):
	l = l.strip().lower()
	if   l.find('axfr') > -1:
		enter(State.AXFR_BEGIN, 'axfr')
	elif l.find('ixfr') > -1:
		enter(State.IXFR_BEGIN, 'ixfr')

# Parse command line options
try:
	opts, args = getopt.getopt(sys.argv[1:], 'hr:', ['help', 'rules'])
except getopt.error, msg:
	print msg
	print 'for help use --help'
	sys.exit(2)
# Options
for o, a in opts:
	if o in ('-r', '--rules') and a != None:
		g_rules = []
		for l in fileinput.input(a):
			l = l.strip().split('\t')
			if len(l) != 2:
				continue
			l[1] = l[1].strip('"').lower()
			g_rules.append((l[0], re.compile(l[1])))
	elif o in ('-h', '--help'):
		print __doc__
		sys.exit(0)

# Difference analysis
if len(args) == 1:
	for rl in fileinput.input(args[0]):
		rl = rl.strip()
		sign = rl[0]	
        	l = re.sub(r'\s+', ' ', rl[1:].lower())
		found = False
        	for s, m in g_rules:
			if m.search(l) != None:
				found = True
				if s == 'mask':
					break
				print '%s ;!%s' % (rl, s.upper())
				break
		if not found:
			print rl
	sys.exit(0)

# Run
for l in fileinput.input('-'):
	l = l.strip()
	if len(l) == 0:
		continue
	if l.startswith(';;'):
		parse_meta(l[3:])
	elif l.startswith(';'):
		parse_opts(l[2:])
	else:
		parse_data(l)
	
