#!/usr/bin/env bash
source "test.case"

_evc() {
	_ev _knotd_compile knot.conf
	if [ "$EVSTR" == "$1" ]; then
		_verbose && _progress " * knotc: compilation of $2 test passed"
	else
		_progress " * knotc: compilation of $2 test failed"
		grep -i "error" zcompile.log|while read l; do _progress "   - $l"; done
	fi
}

ZONE="example.com"
ZF="$BASEDIR/zones/example.com.zone"
ZONES=( $ZONE )
_rc_init

# Generate config and empty zone
_cfg_gen_master ${ZONES[*]} > knot.conf
#_cfg_gen_slave_named ${ZONES[*]} > bind.conf
_generate_zone $ZONE -1

# Generate zones and reload
_ev _knotd_compile knot.conf || _progress " * knotc: zone compilation $EVSTR"
echo "valid0.tlsa52 IN TLSA 0 0 1 d2abde240d7cd3ee6b4b28c54df034b97983a1d16e8a410e4561cb106618e971" >> $ZF
echo "valid1.tlsa52 IN TLSA 3 1 2 d2abde240d7cd3ee6b4b28c54df034b9 7983a1d16e8a410e4561cb106618e972" >> $ZF
echo "valid2.tlsa52 IN TYPE52 \# 67 01010292003BA34942DC74152E2F2C408D29ECA5A520E7F2E06BB944F4DCA346BAF63C1B177615D466F6C4B71C216A50292BD58C9EBDD2F74E38FE51FFD48C43326CBC" >> $ZF
_evc "OK" "valid{0-2}.tlsa52"

# Wildcard to cname not in zone
cp $BASEDIR/zones/$ZONE.zone $BASEDIR/zones/$ZONE.zone.slave
if _knotd_start knot.conf $TIMEOUT; then
#_ev _named_start bind.conf $TIMEOUT || _progress " * named: started $EVSTR"

# Digs
for n in $(seq 0 2); do
	(_dig_knot "-t TYPE52 valid${n}.tlsa52.$ZONE") 2>&1|tee -a digs|grep -qE "^valid${n}.tlsa52.$ZONE" || _progress " * knotd: query for 'valid${n}.tlsa52' FAILED"
done
_knotd_stop
#_named_stop
else
	_rc 1
fi

_test_save
_rc
exit $?
