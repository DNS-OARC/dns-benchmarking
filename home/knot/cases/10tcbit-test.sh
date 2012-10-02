#!/usr/bin/env bash
source "test.case"

_check_tc() {
	tc_set=$(_dig_knot $*|tee -a digs|grep flags|grep -c tc)
	if [ $tc_set -ne 1 ]; then _progress " * knotd: TC bit expected with '$*'"; _rc 1; return 1; fi
	return 0;
}

_check_tc_not() {
	tc_set=$(_dig_knot $*|tee -a digs|grep flags|grep -c tc)
        if [ $tc_set -ne 0 ]; then _progress " * knotd: unexpected TC bit with '$*'"; _rc 1; return 1; fi
        return 0;
}

ZONES="example.com"
ZFILE="$(dirname $0)/files/10tcbit-test.zone"
_rc_init

# Generate config and init testing
_knot_prefix ""
_knotd_memcheck_limits 0 0
_cfg_gen_master ${ZONES[*]} > knot.conf
[ ! -d $BASEDIR/zones ] && mkdir $BASEDIR/zones
cp $ZFILE $BASEDIR/zones/example.com.zone
_ev _knotd_compile knot.conf
if _knotd_start knot.conf $TIMEOUT; then

# Check existing TC bit
_dig_flags ""
_check_tc "example.com DNSKEY +ignore +noedns"
_check_tc "example.com DNSKEY +ignore +dnssec +bufsize=1024"

# Check not existing TC bit
_check_tc_not "example.com DNSKEY +ignore +dnssec +bufsize=4096"
_check_tc_not "example.com DNSKEY +tcp"
_check_tc_not "example.com DNSKEY +tcp +dnssec +bufsize=1024"

_knotd_stop
else
	_rc 1
fi


_test_save
_rc
exit $?
