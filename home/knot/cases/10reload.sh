#!/usr/bin/env bash
source "test.case"

export ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 3) "24/27.5.3.129.in-addr.arpa" )
_rc_init

# Generate config and init testing
_cfg_gen_master ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}
if ! _knotd_start knot.conf $TIMEOUT; then
	_progress " * knotd: failed to start"
	_test_save
	exit 1
fi

# Generate zones and reload
_generate_zones ${ZONES[*]}
_enter $BASEDIR/zones
for z in *.zone; do cp $z $z.slave; done
_leave
_ev _knotd_compile knot.conf || _progress " * knotc: zone compilation $EVSTR"
_ev _knotd_reload knot.conf || _progress " * knotd: reload configuration $EVSTR"
sleep 2
_dig_knot SOA $ZONE &>digs
if [ $? -ne 0 ]; then
	_progress " * knotd: failed to reload zone (more info in knotd.log)"
	_rc 1
fi

# Start BIND
_cfg_gen_slave_named ${ZONES[*]} > bind.conf
_ev _named_start bind.conf $TIMEOUT || _progress " * named: started $EVSTR"

# Compare zones
_dig_fetch_many knot.conf bind.conf ${ZONES[*]} || _progress " * there were some differences in final AXFR"

# Stop BIND
_named_stop
_knotd_stop

_test_save
_rc
exit $?
