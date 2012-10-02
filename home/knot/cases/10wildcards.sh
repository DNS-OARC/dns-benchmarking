#!/usr/bin/env bash
source "test.case"

ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
export ZF="$BASEDIR/zones/$ZONE.zone"
export ZF_S="$BASEDIR/zones/$ZONE.zone.slave"
ZONES=( $ZONE $(_generate_names 19) )
RULES="$BASEDIR/.rules.tmp"
export DIG_FULL_LOG=1 # full dig logging
_rc_init

_chk_rr() {
	name=$1
	shift 1
	_update_soa $ZF
	_update_soa $ZF_S
	_ev _knotd_compile knot.conf;
	if [ $? -gt 0 ] || [ $(grep -c -i error zcompile.log) -gt 0 ]; then
  		_progress " * knotc: '$name' zone compilation $EVSTR"
	fi
	grep -i "error" zcompile.log|grep -v "warning"|while read l; do _progress "   - $l"; done
	_ev _named_start bind.conf $TIMEOUT || _progress " * named: started $EVSTR"
	if ! _knotd_start knot.conf $TIMEOUT; then
		_progress " * knotd: failed to start"
	else
	sleep 2
	_ev _dig_both knot.conf bind.conf $*; _rc $?
	_knotd_stop
	fi
	_named_stop
	mv knotd.log knotd.$name.log
}

# Generate config and init testing
_cfg_gen_master ${ZONES[*]} > knot.conf
_cfg_gen_slave_named ${ZONES[*]} > tmp.conf
sed -i "s/type slave/type master/" tmp.conf
cat tmp.conf|grep -v "masters" > bind.conf
rm tmp.conf
_generate_zones ${ZONES[*]}
_enter $BASEDIR/zones
for z in ${ZONES[*]}; do cp $z.zone $z.zone.slave; done
_leave

# Initialize file with diff rules
_dig_diff_rules $RULES

# Wildcard to cname not in zone
echo -e "warning\t[authority]" > $RULES
SUFFIX="wildcard.example.com"
echo "*.$SUFFIX. IN CNAME wildcard.else.where."|tee -a $ZF >> $ZF_S
_chk_rr 'cname-wc-oo' +nsid a.$SUFFIX

# Wilcard to non-existing name
echo -e "warning\t[authority]" > $RULES
echo "wc-ne IN CNAME non-existing"|tee -a $ZF >> $ZF_S
_chk_rr 'cname-wc-ne' wc-ne.$ZONE

# CNAME resolution to name out-of-zone
echo -e "mask\t[additional]" > $RULES
C1="cname-res-oo"
echo "${C1} IN NS cn.${C1}"|tee -a $ZF >> $ZF_S
echo "cn.${C1} IN CNAME ${C1}.example.cz."| tee -a $ZF >> $ZF_S
_chk_rr $C1 +time=1 NS ${C1}.$ZONE

_test_save
_rc
exit $?
