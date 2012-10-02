#!/usr/bin/env bash
if [ "$(basename $0)" == "21ixfr-out.sh" ]; then
	source "test.case"
fi

ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 3) "24/27.5.3.129.in-addr.arpa" )
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}
for z in ${ZONES[*]}; do
	zp=$(_zpath $z)
	cp $zp $zp.base;
done
_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
_rc && _knotd_wait_axfr ${ZONES[*]}
if _rc; then
        updated=( $(_arr_selection ${ZONES[*]}) )
        _generate_zones_update ${updated[*]}
        _named_reload
        _knotd_wait_ixfr ${updated[*]}
fi
# Reload BIND as slave
_verbose && _progress " * named: reloading to try IXFR/IN from Knot"
_named_stop
cp named.log named.xfers.log
_enter $BASEDIR/zones
rm *.jnl &>>$LOG
for z in ${ZONES[@]}; do 
	zp=$(_zpath $z)
	cp $zp.base $zp;
done
_leave
cp bind.conf bind.xfers.conf
_cfg_gen_transit_named ${ZONES[*]} > bind.conf
_named_start bind.conf $TIMEOUT
_named_refresh ${updated[*]}
_named_wait_ixfr ${updated[*]}

# Evaluate
_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
_knotd_stop
_named_stop
_test_save

_rc
exit $?
