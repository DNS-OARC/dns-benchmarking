#!/usr/bin/env bash
if [ "$(basename $0)" == "20ixfr-in.sh" ]; then
        source "test.case"
fi

ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 9) )
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}
_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
_rc && _knotd_wait_axfr ${ZONES[*]}
if _rc; then
	updated=( $(_arr_selection ${ZONES[*]}) )
	_generate_zones_update ${updated[*]}
	_named_reload
	_knotd_wait_ixfr ${updated[*]}
fi
_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
_knotd_stop
_named_stop
_test_save

_rc
exit $?
