#!/usr/bin/env bash
if [ "$(basename $0)" == "21double-sign.sh" ]; then
	source "test.case"
fi

_ZONES_SIGNED=1
ZONE="example.com"; [ $# -ge 1 ] && ZONE="$1"
GENZONES=( $(_generate_names 3) )
ZONES=( $ZONE ${GENZONES[*]} )
_rc_init
_generate_zones ${GENZONES[*]}
_generate_zone -t 3600 ${ZONE} 1000

# Double-sign '$ZONE'
_sign_zone $ZONE -3 deadbeef -T 3600
_sign_zone ALTKEY $ZONE -3 cafebabe -T 3600
_enter $BASEDIR/zones
for z in ${ZONES[*]}; do cp $z.zone $z.base; done
_leave

# Try to compile and regenerate config
_cfg_gen_slave ${ZONE} > knot.conf
cp $BASEDIR/zones/$ZONE.zone $BASEDIR/zones/$ZONE.zone.slave
if ! _knotd_compile knot.conf; then
	_progress " * knotd: failed to compile zone signed with 2 different KSKs" 
	exit 1
else
	_verbose && _progress " * knotd: successfuly compiled zone with 2 different KSKs"	
fi
rm $BASEDIR/zones/$ZONE.zone.slave
_cfg_gen_slave ${ZONES[*]} > knot.conf

# Try to transfer with AXFR
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
_rc && _knotd_wait_axfr ${ZONES[*]}
if _rc; then
	# Resign both
	_sign_zone $ZONE -3 deadbeef -T 3600
	_sign_zone ALTKEY $ZONE -3 cafebabe -T 3600
	_update_soa $ZONE
	_generate_zones_update ${GENZONES[*]}
        _named_reload
        _knotd_wait_ixfr ${ZONES[*]}
fi
# Reload BIND as slave
_verbose && _progress " * named: reloading to try IXFR/IN from Knot"
_named_stop
cp named.log named.xfers.log
_enter $BASEDIR/zones
for z in ${ZONES[@]}; do 
rm "${z}.zone.jnl" &>>$LOG
cp "${z}.base" "${z}.zone"
done
_leave
cp bind.conf bind.xfers.conf
_cfg_gen_transit_named ${ZONES[*]} > bind.conf
_named_start bind.conf $TIMEOUT
_named_refresh ${ZONES[*]}
_named_wait_ixfr ${ZONES[*]}

# Evaluate
_rc && _dig_fetch_many knot.conf bind.conf ${ZONES[*]}
_knotd_stop
_named_stop
_test_save

_rc
exit $?
