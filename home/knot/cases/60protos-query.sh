#!/usr/bin/env bash
source "test.case"

# Protos
protos="$(dirname $0)/protos/c09-dns-query-r1.jar"
protos_args="--delay 10"
_protos() {
	java -jar $protos $protos_args $*
	return $?
}

# Defaults
ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 9) )

# Setup server
_cfg_gen_master ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}
_knotd_start knot.conf $TIMEOUT
if [ $? -ne 0 ]; then
	_test_save
	exit 1
fi

# Run PROTOS
iface=($(_knot_iface knot.conf))
_verbose && _progress " * protos: protos-query starting"
_protos --host ${iface[0]} --port ${iface[1]} --index 8000-9000 &> protos-query.log
#_protos --host ${iface[0]} --port ${iface[1]} &> protos-query.log
errs=$(grep ERROR protos-query.log|wc -l)
if [ "$errs" -gt 0 ]; then
	_progress " * protos: protos-query finished with $errs errors"
	# Save errors only
        ret=1
	_rc $ret
else
         _verbose && _progress " * protos: finished with no errors, OK"
fi

# Save trimmed log
grep -v -E "(127.0.0.1|completed|delay of)" protos-query.log > tmp.log; mv tmp.log protos-query.log

# Stop Knot
_knotd_stop
_test_save
_rc
exit $?
