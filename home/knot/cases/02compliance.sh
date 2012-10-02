#!/usr/bin/env bash
source "test.case"

# Parameters
export ACTION="";
if [ "$1" == "--knot" ]; then
	ACTION="knot";
	shift 1
fi
ts_key="key0.tsig"
ts_s="cHJvcGhldAo="
_tsig_use "$ts_key" "hmac-md5" "$ts_s"

# Generate zones
_ZONES_SIGNED=1 # Disable random zone signing
ZONES=( unsigned signed )
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_master_nsd ${ZONES[*]} > nsd.conf
_cfg_gen_master ${ZONES[*]} > knot.conf

# Prepare query mixes
cd $BASEDIR
export REG_DIR="/var/cache/knot-tests/regressions"
if [ ! -d $REG_DIR ]; then
	_progress " * generating testing zones (${ZONES[*]})"
	_generate_zones_size 1000 5000
	_generate_zones ${ZONES[*]}
	_generate_zone -t 3600 signed 1000
	cat >> zone.extend << EOF
cn-notexists     CNAME out-of-zone
nsec3-trr1       A       1.2.3.4
*.nsec3-trr2     A       1.2.3.4
*.nsec3-test1    CNAME   nsec3-trr1
*.nsec3-test2    CNAME   nsec3-test1
*.nsec3-test3    CNAME   non-existing
nsec3-test4      CNAME   nsec3-trr1.nsec3-trr2
*.nsec3-test5    CNAME   nsec3-trr1.nsec3-trr2
*.nsec3-test6    CNAME   a.nsec3-test5
dname-t0         DNAME   dname-t1
dname-t0.dname-t1 A      1.2.3.4
dname-t2         DNAME   dname-somewhere-else.
*.a-wrr          A       4.3.2.1
ns-wrr           NS      ns1.a-wrr
mx-wrr           MX      1 mx1.a-wrr
ptr-wrr          PTR     ptr1.a-wrr
afsdb-wrr        AFSDB   1 afsdb1.a-wrr
_sip._tcp.srv-wrr SRV    10 10 1234 sip1.a-wrr
wc001            CNAME   wc001.wc002
*.wc002          A       1.2.3.4
EOF
	cat zone.extend >> $BASEDIR/zones/unsigned.zone
	cat zone.extend >> $BASEDIR/zones/signed.zone
	rm zone.extend
        _sign_zone signed -3 deadbeef -T 3600 -O full
        cat $BASEDIR/zones/signed.zone|grep NSEC3 > nschain1.tmp
        _sign_zone ALTKEY signed -3 cafebabe -T 3600 -O full
        cat nschain1.tmp >> $BASEDIR/zones/signed.zone
	rm nschain1.tmp

	mkdir -p $REG_DIR
	cp $BASEDIR/zones/*.zone $REG_DIR/
	_pcap_gen "unsigned" -y "$ts_key:$ts_s" &>>$REG_DIR/qr-unsigned.gen.log; mv unsigned.pcap $REG_DIR/qr-unsigned.pcap
	_pcap_gen "signed" -y "$ts_key:$ts_s" &>>$REG_DIR/qr-signed.gen.log; mv signed.pcap $REG_DIR/qr-signed.pcap
else
	[ ! -d $BASEDIR/zones ] && mkdir $BASEDIR/zones
	cp $REG_DIR/*.zone $BASEDIR/zones/
fi

# Check for errors in replay
# ( function_on_exit )
_check_replay_errors() {
        errs=$(cat replay-errors.log|wc -l) 
        if [ $errs -gt 0 ]; then
                _progress " * detected '$errs' errors during replaying, see 'regressions/replay-errors.log'"
                _progress " * results would be inconclusive, refusing to compare"
                mv replay-errors.log $BASEDIR/regressions/
		$*
                _test_save
                exit 1
        else
		$*
                rm replay-errors.log
        fi
}

knotd_rev=$(_knotd_rev)
if [ "$knotd_rev" != "" ]; then
	knotd_rev="-git.$knotd_rev"
fi

# Query Knot,BIND,NSD
mkdir regressions
_progress " * querying 'knot-$(_knotd_ver)${knotd_rev}'"
if _knotd_start knot.conf $TIMEOUT; then
	iface=( $(_knot_iface knot.conf) )
	_replay ${iface[1]} $REG_DIR/qr-unsigned.pcap > regressions/unsigned-knotd.pcat 2>>replay-errors.log
	_replay ${iface[1]} $REG_DIR/qr-signed.pcap > regressions/signed-knotd.pcat 2>>replay-errors.log
	_check_replay_errors _knotd_stop
	if [ ! -d $REG_DIR/base ]; then
		mkdir $REG_DIR/base
		cp regressions/unsigned-knotd.pcat $REG_DIR/base/unsigned-base.pcat
		cp regressions/signed-knotd.pcat $REG_DIR/base/signed-base.pcat
		echo "$(_knotd_ver)" >> $REG_DIR/base/info
	fi
else
	_test_save
	exit 2
fi

if [ "$ACTION" == "knot" ]; then
	_test_save
	exit 0
fi

_progress " * querying 'bind-$(_named_ver)"
if _named_start bind.conf $TIMEOUT; then
	iface=( $(_named_iface bind.conf) )
	_replay ${iface[1]} $REG_DIR/qr-unsigned.pcap > regressions/unsigned-named.pcat 2>>replay-errors.log
	_replay ${iface[1]} $REG_DIR/qr-signed.pcap > regressions/signed-named.pcat 2>>replay-errors.log
	_check_replay_errors _named_stop
else
	_test_save
	exit 2
fi

_progress " * querying 'nsd-$(_nsd_ver)'"
if _nsd_start nsd.conf $TIMEOUT; then
	iface=( $(_nsd_iface nsd.conf) )
	_replay ${iface[1]} $REG_DIR/qr-unsigned.pcap > regressions/unsigned-nsd.pcat 2>>replay-errors.log
	_replay ${iface[1]} $REG_DIR/qr-signed.pcap > regressions/signed-nsd.pcat 2>>replay-errors.log
	_check_replay_errors _nsd_stop
else
	_test_save
	exit 2
fi

# Analyze differences between tested implementations
cd $BASEDIR/regressions
_pcat_cmp "unsigned-named.pcat" "unsigned-knotd.pcat" "unsigned-named-knotd.log"
_pcat_cmp "unsigned-nsd.pcat" "unsigned-knotd.pcat" "unsigned-nsd-knotd.log"
_pcat_cmp "signed-named.pcat" "signed-knotd.pcat" "signed-named-knotd.log"
_pcat_cmp "signed-nsd.pcat" "signed-knotd.pcat" "signed-nsd-knotd.log"

# Store graphs
[ ! -d $BASEDIR/graphs ] && mkdir $BASEDIR/graphs
adiff-g.sh png unsigned-knotd.pcat unsigned-named.pcat unsigned-nsd.pcat &>>$LOG; mv adiff.png $BASEDIR/graphs/unsigned-differences.png
adiff-g.sh png signed-knotd.pcat signed-named.pcat signed-nsd.pcat &>>$LOG; mv adiff.png $BASEDIR/graphs/signed-differences.png

# Convert to pcaps
for f in *.pcat; do
        pcat2pcap.sh $f &>/dev/null || true
        mv "${f}.tr" "${f%pcat}pcap" &>/dev/null || true
done
cd $BASEDIR

_test_save
_rc
exit $?
