#!/usr/bin/env bash
if [ "$(basename $0)" == "20ixfr-in-existing-rr.sh" ]; then
        source "test.case"
fi

_ZONES_SIGNED=1
ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE )
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}

# Forge existing RR into slave zone
zp=$(_zpath $ZONE); cp $zp $zp.slave
echo "existing-rr A 1.2.3.4" >> $zp.slave

_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
if _rc; then
	echo "existing-rr A 1.2.3.4" >> $zp
	_update_soa $ZONE
	sleep 2
	_named_reload
	_knotd_wait_ixfr ${ZONES[*]}
fi

_dig_knot A existing-rr.$ZONE &> digs
_dig_both knot.conf bind.conf A existing-rr.$ZONE; _rc $?
_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
_knotd_stop
_named_stop
_test_save

_rc
exit $?
