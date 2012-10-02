#!/usr/bin/env bash
source "test.case"

ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE )
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}

# Insert CNAME loop
echo "loop CNAME loop" >> $BASEDIR/zones/$ZONE.zone
_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
if _rc; then
        _watch $KNOTD_PID - - knotd.log "CNAME loop found in zone" $TIMEOUT $KNOTD_LL
        if [ $? -eq 0 ]; then
		_progress " * knotd: CNAME loop not transferred, OK"
		_dig_knot loop.$ZONE &>>$LOG
        else
        	_verbose && _progress " * knotd: timeout exceeded while waiting for AXFR/IN of '$z'"
        fi
fi
_knotd_stop
_named_stop
_test_save

_rc
exit $?
