#!/usr/bin/env bash
if [ "$(basename $0)" == "13axfr-in-knotonly.sh" ]; then
        source "test.case"
fi

ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 19) )
#_knot_prefix "valgrind --leak-check=full --track-origins=yes"
_rc_init
_cfg_gen_slave ${ZONES[*]} > knot.conf
_cfg_gen_master ${ZONES[*]} > master.conf
_generate_zones ${ZONES[*]}
knotc -c master.conf compile &>knotc.log || _progress " * knotc: zone compilation FAILED"
knotd -c master.conf &>knotd-master.log &
mpid=$!
if _rc; then
	$KNOT_BIN -c knot.conf &>knotd.log &
        export KNOTD_PID=$!
	_knotd_wait_axfr ${ZONES[*]}
fi
kill $mpid
kill $KNOTD_PID
wait $mpid
wait $KNOTD_PID
_test_save

_rc
exit $?
