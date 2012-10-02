#!/usr/bin/env bash
source "test.case"

KEY="keizaal"
SECRET=$(_rnd_str 10|base64)
ISECRET=$(echo "invalid"|base64)
_tsig_use "$KEY" "hmac-md5" "$SECRET"

ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 19) )
_rc_init

# Generate config and init testing
_cfg_gen_master ${ZONES[*]} > knot.conf
_generate_zones ${ZONES[*]}
_enter $BASEDIR/zones
for z in ${ZONES[*]}; do cp $z.zone $z.zone.slave; done
_leave
if ! _knotd_start knot.conf $TIMEOUT; then
	_test_save
	exit 1
fi
_cfg_gen_slave_named ${ZONES[*]} > bind.conf
_ev _named_start bind.conf $TIMEOUT || _progress " * named: started $EVSTR"

# TSIG scenarios
cat > tsig-queries.log << EOF
-y ${KEY}.noent:${SECRET} ns.$ZONE
-y ${KEY}:${ISECRET} ns.$ZONE
-y hmac-sha1:${KEY}:${SECRET} ns.$ZONE
EOF

_tsig_filt() {
	while read l; do
		echo $l|grep -qi tsig
		if [ $? -eq 0 ]; then
			echo $l|awk '{print $1,$2,$3,$4,$5,$7,$8,$10,$11}'
		else
			echo $l
		fi
	done
}
_tsig_filt_stop() {
	return 0
}

# Perform TSIG queries
_dig_filt _tsig_filt
_dig_both_file knot.conf bind.conf tsig-queries.log
_rc $?
_dig_filt

_named_stop
_knotd_stop
_test_save
_rc
exit $?
