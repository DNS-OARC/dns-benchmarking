#!/usr/bin/env python
import sys, getopt
from scapy.all import *
from pydig_mod import *
base = ''
target = ''
inspect_id = -1

# Usage
def usage():
        print "%s: [-h] <base> <target>" % sys.argv[0]
        print "Parameters:"
        print "\t-h,--help\tHelp."
        print "\t-i X,--inspect X\tInspect packet X."

# Parse options
try:
        opts, args = getopt.getopt(sys.argv[1:], "i:h", ['inspect','help'])
except getopt.GetoptError, err:
        usage()
        sys.exit(1)
for o, a in opts:
	if o in ('-i', '--inspect'):
		inspect_id = int(a)
	elif o in ('-h', '--help'):
		usage()
		sys.exit(1)
	else:
		usage()
		sys.exit(1)

# Arguments
if len(args) > 2:
        print 'Too many arguments, for help use --help'
        sys.exit(2)
if len(args) < 2:
        print 'Too few arguments, for help use --help'
        sys.exit(2)
base = open(args[0])
target = open(args[1])

# Safe intval
def intval(s):
	try:
		return int(s)
	except ValueError:
		return -1
# Printable c
def pchr(c):
	if ord(c) < ord('0') or ord(c) > ord('z'):
		return '\\%u' % ord(c)
	return c

# Printable string
def pstr(s): return ''.join([pchr(c) for c in s])

# Packet parsing log filter
class ParseFilter(logging.Filter):
	pktid = 0
	origin = ''
	def filter(self, record):
		print '%u %s: %s' % (self.pktid, self.origin, record.msg)
		raise Exception
		return 0

# Formatter setup
pktfilt = ParseFilter()
logging.getLogger('scapy.runtime').addFilter(pktfilt)

# Differences logging
def dlog(i, t, s):
	print '%u %s: %s' % (i, t, s)
	return 1

# RR type name
ttable = dnstypes
ttable[250] = 'TSIG'
ttable[41] = 'OPT'
ttable[50] = 'NSEC3'
ttable[46] = 'RRSIG'
def rrtype_str(t):
	try:
		return ttable[t]
	except KeyError:
		return str(t)

# rcode names
rctable = {0:'NOERROR',1:'FORMERR',2:'SERVFAIL',3:'NXDOMAIN',4:'NOTIMPL',
           5:'REFUSED',9:'NOTAUTH',16:'BADVERS',17:'BADKEY',18:'BADTIME',
           19:'BADMODE',20:'BADNAME',21:'BADALG',22:'BADTRUNC'}
def rcode_str(t):
	try:
		return rctable[t]
	except KeyError:
		return str(t)

# rdata descriptors
tsig_desc = ['algorithm', 'sigtime', 'fudge', 'mac_len', 'mac', 'orig_id', 'retcode', 'other_len', 'other_data']

# RDATA analyzer
# @b base RR
# @t target RR (evaluated)
# @prefix prefix for composed message (if difference found)
# @pb full base packet (for compression resolution)
# @pt full target packet
def analyze_rdata(b, t, prefix, pb, pt):
	rrb = None
	rrt = None
	rrts = rrtype_str(b.type)
	desc = prefix + 'rtype=%s, base != target' % rrts
	desc_spec = prefix + 'rtype=%s, ' % rrts + '\'%s\' != \'%s\''
	try:

		# Decode TSIG RR
		if b.type == 250:
			# Presume as similar unless we find a difference
			desc = prefix + 'TSIG.%s \'%s\' != \'%s\''
			ts_b = Tsig(); ts_b.keyname = b.rrname
			ts_b = ts_b.decode_tsig_rdata(str(b.rdata), 0, b.rdlen, b.rrname, 0).split(' ')
			ts_t = Tsig(); ts_t.keyname = t.rrname
			ts_t = ts_t.decode_tsig_rdata(str(t.rdata), 0, t.rdlen, t.rrname, 0).split(' ')
			# Convert other_data
			if len(ts_b) == 9: ts_b[8] = ts_b[8].encode('hex')
			if len(ts_t) == 9: ts_t[8] = ts_t[8].encode('hex')
			# Ignore BADTIME other_data value
			if ts_b[6] == ts_t[6] and ts_b[6] == 'BADTIME':
				ts_b[8] = ts_t[8] = ''
			# Ignore sigtime, as it's always different
			ts_b[1] = ts_t[1] = 0
			# Unfortunately, TSIG server time is always different, so skip MAC
			ts_b[4] = ts_t[4] = 0
			# Find difference
			found_diff = False
			for k in xrange(0, len(ts_b) - 1):
				if ts_b[k] != ts_t[k]:
					desc = desc % (tsig_desc[k], str(ts_b[k]), str(ts_t[k]))
					found_diff = True
					break
			# Clear TSIGs without a difference
			if not found_diff:
				return (0, 'tsig', 'OK')
		# NS
		elif b.type in [2, 5, 12, 39]:
			bdn = str(b.rdata).lower()
			tdn = str(t.rdata).lower()
			if bdn == tdn:
				return (0, 'ns', 'OK')
			desc = desc_spec % (bdn, tdn)
		# MX
		elif b.type == 15:
			br = decode_mx_rdata(str(b.rdata), 0, b.rdlen, str(pb)).lower().split(' ')
			tr = decode_mx_rdata(str(t.rdata), 0, t.rdlen, str(pt)).lower().split(' ')
			if br[0] != tr[0]:
				desc = desc_spec % (br[0], tr[0]) + ' (MX_PREF)'
			elif br[1] != tr[1]:
				desc = desc_spec % (br[1], tr[1]) + ' (MX_NAME)'
			else:
				return (0, 'mx', 'OK')
		# AFSDB
		elif b.type == 18:
			br = decode_mx_rdata(str(b.rdata), 0, b.rdlen, str(pb)).lower().split(' ')
			tr = decode_mx_rdata(str(t.rdata), 0, t.rdlen, str(pt)).lower().split(' ')
			if br[0] != tr[0]:
				desc = desc_spec % (br[0], tr[0]) + ' (SUBTYPE)'
			elif br[1] != tr[1]:
				desc = desc_spec % (br[1], tr[1]) + ' (HOSTNAME)'
			else:
				return (0, 'mx', 'OK')
		# SOA
		elif b.type == 6:
			bs = decode_soa_rdata(str(b.rdata), 0, b.rdlen, str(pb)).lower()
			ts = decode_soa_rdata(str(t.rdata), 0, t.rdlen, str(pt)).lower()
			if bs == ts:
				return (0, 'soa', 'OK')
			desc = desc_spec % (bs, ts)
		# RP
		elif b.type == 17:
			brp = decode_rp_rdata(str(b.rdata), 0, b.rdlen, str(pb)).lower().split(' ')
			trp = decode_rp_rdata(str(t.rdata), 0, t.rdlen, str(pt)).lower().split(' ')
			if brp[0] != trp[0]:
				desc = desc_spec % (brp[0], trp[0]) + ' (RP_MBOX)'
			elif brp[1] != trp[1]:
				desc = desc_spec % (brp[1], trp[1]) + ' (RP_TXT)'
			else:
				return (0, 'rp', 'OK')
		# OPT
		elif b.type == 41:
			bo = decode_opt_rdata(str(b.rdata), 0, b.rdlen, b.ttl, str(pb)).lower().split(' ')
			to = decode_opt_rdata(str(t.rdata), 0, t.rdlen, t.ttl, str(pt)).lower().split(' ')
			rrf_dv = ['EDNS_VER','EXRCODE','FLAGS','RDLEN','RDATA']
			found_diff = False
			for i in xrange(0,len(bo)):
				if bo[i] != to[i]:
					desc = desc_spec % (bo[i], to[i])
					desc += ' (%s)' % rrf_dv[i]
					found_diff = True
					break
			if not found_diff:
				return (0, 'opt', 'OK')
		# Unknown RR
		else:
			desc += ' (not dissected)'

	except KeyError:
		desc += ' (could not parse %s RR)'
		if rrb is None:
			desc = desc % 'base'
		elif rrt is None:
			desc = desc % 'target'

	# generic analyzer
	return (1, 'rdata', desc)
	
# RR analyzer
# @j index of base RR in section
# @k index of target RR in section
# @b base RR
# @t target RR (evaluated)
# @name symbolic section name
# @pb full base packet (for compression resolution)
# @pt full target packet
def analyze_rr(j, k, b, t, name, pb, pt):
	dstr = name + '[%u->%u]' % (j,k) + '.%s, '
	dstr_vs = dstr + '%s != %s'

	# compare name
	if b.rrname.lower()  != t.rrname.lower():
		return (1, 'rrname', dstr_vs % ('rrname', b.rrname, t.rrname))
	# compare type
	if b.type != t.type:
		return (1, 'rrtype', dstr_vs % \
		('rrtype', rrtype_str(b.type), rrtype_str(t.type)))
	# compare rclass
	if b.rclass != t.rclass:
		return (1, 'rclass', dstr_vs % \
		('rclass', dnsclasses[b.rclass], dnsclasses[t.rclass]))
	# compare ttl
	if b.ttl != t.ttl:
		return (1, 'ttl', dstr_vs % \
		('ttl', str(b.ttl), str(t.ttl)))
	# compare rdata
	if b.rdata != t.rdata:
		return analyze_rdata(b, t, dstr % ('rdata'), pb, pt)

        return (0, 'rr', '')
        
# RRs analyzer (autoselects best RR pairing)
# @i packet id
# @b base answer
# @t target answer (evaluated)
# @name symbolic section name
# @pb full base packet (for compression resolution)
# @pt full target packet
def analyze_rrs(i, b, t, name, count, pb, pt):
	if count == 0: return 0
	for j in xrange(0, count):
		matches = []
		# pick candidates
		for k in xrange(0, count):
			if b[j].rrname.lower() == t[k].rrname.lower() and b[j].type == t[k].type:
				matches.append(k)
		if len(matches) == 0:
			matches.append(j)
		# evaluate all candidates
		results = []
		for k in matches:
			rc,s,msg = analyze_rr(j, k, b[j], t[k], name, pb, pt)
			# perfect match found
			if rc == 0:
				results = [] # clear results
				break
			else:
				results.append((rc,s,msg))
		# if no perfect match found, pick first difference
		if len(results) > 0:
			rc,s,msg = results[0]
			return dlog(i,s,msg)
	return 0
		

# Question analyzer (Scapy has slightly different syntax)
# @i packet id
# @b base answer
# @t target answer (evaluated)
# @name question section symbolic name
# @count number of records
def analyze_qd(i, b, t, name, count):
	if count != 1:
		return 0
	dstr = name + '[%u].%s, '
	dstr_vs = dstr + '%s != %s'
	# compare name
	if b.qname.lower() != t.qname.lower():
		return dlog(i, 'qname', dstr_vs % \
		(j, 'qname', b.qname, t.qname))
	# compare type
	if b.qtype != t.qtype:
		return dlog(i, 'qtype', dstr_vs % \
		(j, 'qtype', rrtype_str(b.qtype), rrtype_str(t.qtype)))
	# compare rclass
	if b.qclass != t.qclass:
		return dlog(i, 'qclass', dstr_vs % \
		(j, 'qclass', dnsclasses[b.qclass], dnsclasses[b.qclass]))

# Analyzer
# @i packet id
# @b base answer
# @t target answer (evaluated)
def analyze(i, b, t, verb):
	if b == t and not verb:
		return 0

	rb = b.decode('hex'); rt = t.decode('hex')
	try:
		pktfilt.pktid = i
		pktfilt.origin = 'parse-base'
		b = DNS(b.decode('hex'))
		pktfilt.origin = 'parse-target'
		t = DNS(t.decode('hex'))
	except:
		return 1
		
	# verbose
	if verb:
		print
		print 'Answer from base set:'
		print '---------------------'
		ls(b)
		print
		print 'Answer from target set:'
		print '-----------------------'
		ls(t)
		print
		print 'Result:'

	# rcode mismatch
	btdiff = '%s != %s'
	if (b.opcode != t.opcode):
		return dlog(i, 'opcode', btdiff % (b.opcode, t.opcode))
	# opcode mismatch
	if (b.rcode != t.rcode):
		return dlog(i, 'rcode', btdiff % (rcode_str(b.rcode), rcode_str(t.rcode)))
	# aa mismatch
	if (b.aa != t.aa):
		return dlog(i, 'aa', btdiff % (b.aa, t.aa))
	# tc mismatch
	if (b.tc != t.tc):
		return dlog(i, 'tc', btdiff % (b.tc, t.tc))
	# rd mismatch
	if (b.rd != t.rd):
		return dlog(i, 'rd', btdiff % (b.rd, t.rd))
	# ra mismatch
	if (b.ra != t.ra):
		return dlog(i, 'ra', btdiff % (b.ra, t.ra))
	# compare QUESTION
	if (b.qdcount != t.qdcount):
		return dlog(i, 'qdcount', btdiff % (b.qdcount, t.qdcount))
	if analyze_qd(i, b.qd, t.qd, 'question', b.qdcount) > 0:
		return 1
	# compare ANSWER
	if (b.ancount != t.ancount):
		return dlog(i, 'ancount', btdiff % (b.ancount, t.ancount))
	if analyze_rrs(i, b.an, t.an, 'answer', b.ancount, rb, rt) > 0:
		return 1
	# compare AUTHORITY
	if (b.nscount != t.nscount):
		return dlog(i, 'nscount', btdiff % (b.nscount, t.nscount))
	if analyze_rrs(i, b.ns, t.ns, 'authority', b.nscount, rb, rt) > 0:
		return 1
	# compare ADDITIONAL
	if (b.arcount != t.arcount):
		return dlog(i, 'arcount', btdiff % (b.arcount, t.arcount))
	if analyze_rrs(i, b.ar, t.ar, 'additional', b.arcount, rb, rt) > 0:
		return 1
	# unhandled error
	#pos = 0
	#for pos in xrange(0, len(rt) - 1):
	#	if len(rb) < pos or rb[pos] != rt[pos]:
	#		break
	#dlog(i, 'unknown', 'position %u' % (pos / 2))
	#return 1
	return 0

# Read lines
pkt = 1
tl = '$'
bl = '$'
t_different = 0
while len(bl) > 0:
	# Find next packet id
	bl = base.readline()
	if intval(bl.strip()) != pkt:
		continue
	# Find packet in in target
	ln_found = False
	skipped = 0
	while not ln_found and len(tl) > 0:
		tl = target.readline()
		ln_found = (intval(tl.strip()) == pkt)
	# Target file ended early
	if not ln_found:
		break
	# Inspect id
	inspecting = False
	if inspect_id > -1:
		if pkt == inspect_id:
			print 'Inspecting packet #%u' % inspect_id
			inspecting = True

	# Skip question
	base.readline()
	target.readline()
	# Read answers
	a1 = base.readline().strip()
	a2 = target.readline().strip()
	# Evaluate
	if inspect_id < 0 or inspecting:
		if analyze(pkt, a1, a2, inspecting) != 0:
			t_different += 1
	# End of inspection
	if inspecting:
		break
	# Find next packet
	pkt += 1

t_answers = pkt - 1
if inspect_id < 0:
	print '======================================='
	print 'Replies:             %u' % t_answers
	print 'Different_replies:   %u   %.02f%%' % (t_different, 100.0 * t_different / float(t_answers))
