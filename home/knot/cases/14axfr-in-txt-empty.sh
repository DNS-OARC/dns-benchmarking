#!/usr/bin/env bash
source "test.case"
ZFILE="$(dirname $0)/files/dnstester.cz.zone"
ZONE="dnstester.cz"
ZONES=( $ZONE )

_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
[ ! -d $BASEDIR/zones ] && mkdir $BASEDIR/zones
cp $ZFILE $BASEDIR/zones/

_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
if _rc; then
	_knotd_wait_axfr ${ZONES[*]}
	_dig_fetch_many knot.conf bind.conf ${ZONES[*]}
fi

_ev _knotd_compile -f knot.conf || _progress " * knotc: zone compilation $EVSTR"

_knotd_stop
_named_stop
_test_save

_rc
exit $?
