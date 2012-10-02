#!/usr/bin/env bash
source "test.case"

_ZONES_SIGNED=1 # Disable signed zones
ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 3) )
COUNT=200
RUN=0

_knotd_quiet 1
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones_size 100 1000
_generate_zones ${ZONES[*]}
sleep 5 # wait for OS to release ports, is stuck from time to time
_named_start bind.conf $TIMEOUT
_knotd_bin "unittests-xfr -z $ZONE"
_knotd_start knot.conf $TIMEOUT
_rc && _knotd_wait_axfr ${ZONES[*]}
_progress " * zones: simulating $COUNT zone updates"
ret=$?; while [ $ret -eq 0 ] && [ $RUN -lt $COUNT ]; do
	# Update generated zones
        #_generate_zones_update ${ZONES[*]}
	#_update_soa "$BASEDIR/zones/$ZONE.zone"
	_generate_zones_update ${ZONE}
	sleep 1
	# Wait for IXFR/IN
        _named_reload
        _knotd_wait_ixfr ${ZONE} || _progress " * knotd: IXFR/IN run #$RUN failed"
	# Integrity check
	_knotd_check_integrity || _progress " * knotd: integrity check run #$RUN failed"
	# Check if still alive
	kill -0 $KNOTD_PID &>/dev/null;
	if [ $? -gt 0 ]; then 
		_progress " * knotd: crash detected, refusing to continue tests"
		ret=1
	fi
	(( RUN += 1 ))
	if (( $RUN % 50 == 0 )); then
		_progress " * knotd: $RUN/$COUNT transfers done"
	fi
done
TIMEOUT=1200
_dig_fetch_many knot.conf bind.conf $ZONE
_knotd_stop
cp $BASEDIR/knotd.log $BASEDIR/knotd.xfers.log
if _rc; then
	_progress " * knotd: restarting to load changes from journal"
	_knotd_start knot.conf $TIMEOUT
	_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
	_knotd_stop
fi
_named_stop
_test_save
_rc
exit $?

