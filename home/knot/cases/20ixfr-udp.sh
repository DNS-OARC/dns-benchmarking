#!/usr/bin/env bash
source "test.case"

ZONE="example.com"
ZONES=( $ZONE )
_rc_init

# Generate zone
[ ! -d $BASEDIR/zones ] && mkdir $BASEDIR/zones
cat >> $BASEDIR/zones/$ZONE.zone << EOF
\$ORIGIN $ZONE.
@       SOA     ns.$ZONE. hostmaster.$ZONE. 1 10800 360 3600 3600
	NS	ns
	NS	ns.else.	
	A	1.2.3.4
EOF

# Generate config and init testing
_cfg_gen_master ${ZONES[*]} > knot.conf
_knotd_start knot.conf $TIMEOUT
if _rc; then
	# Start tunnel
	TUN_PORT=44444
	iface=( $(_knot_iface knot.conf) )
	dns-tcp2udp.py ${TUN_PORT}-${iface[1]} &>tcp2udp.log &
	TUN_PID=$!
	sleep 1

	# Dig
	ret=$( _dig @${iface[0]} -p $TUN_PORT ixfr=1 $ZONE | tee digs | grep -c NOERROR )
	if [ $ret -ne 1 ]; then
		s=$(tail -n 1 digs); s=${s:2}
		_progress " * IXFR/UDP query failed - $s (expected SOA response)"
		_rc 1
	fi

	# Stop tunnel
	kill $TUN_PID
	sleep 1
fi

_knotd_stop
_test_save
_rc
exit $?
