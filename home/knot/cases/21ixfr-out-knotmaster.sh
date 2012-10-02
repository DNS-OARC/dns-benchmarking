#!/usr/bin/env bash
if [ "$(basename $0)" == "21ixfr-out-knotmaster.sh" ]; then
        source "test.case"
fi

ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 9) )
_rc_init
_cfg_gen_master ${ZONES[*]} > knot.conf
_cfg_gen_slave_named ${ZONES[*]} > bind.conf
_generate_zones ${ZONES[*]}
_knotd_start knot.conf $TIMEOUT
_named_start bind.conf $TIMEOUT
_rc && _named_wait_axfr ${ZONES[*]}
if _rc; then
	updated=( $(_arr_selection ${ZONES[*]}) )
	_generate_zones_update ${updated[*]}
	_knotd_compile knot.conf
	_knotd_reload knot.conf
	_named_wait_ixfr ${updated[*]}
fi
_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
_named_stop
_knotd_stop
_test_save

_rc
exit $?
