#!/usr/bin/env bash
source "test.case"

export DIG_FULL_LOG=1 # full dig logging
FILES=$(dirname $0)/files
ZONE="example.com"
ZONES=( $ZONE )
_rc_init

# Generate config and init testing
_cfg_gen_master ${ZONES[*]} > knot.conf
[ ! -d $BASEDIR/zones ] && mkdir $BASEDIR/zones
cp $FILES/$ZONE.zone.signed $BASEDIR/zones/$ZONE.zone

# Extend zone
cat >> $BASEDIR/zones/$ZONE.zone << EOF
onlysig.normal                  3600    RRSIG   A 7 3 3600 20120311114108 (
                                        20120210114108 60914 example.com.
                                        Bh6S2as2/EjwihXV5FM8hC9urhLMcXCyhXwX
                                        l+/cRM/8Rd0hKZEcoMVN5U8f163hZQgueRA8
                                        J2n8kPSQ3tdEURCkaYdvgU332pJgBpaibWYu
                                        KrkvyPhK/4YkMYkAj245ioHOln8G0wkf6oTW
                                        8dpM5JsAvSAckJ2tK0fBIreM07M= )
onlysig.dname                   3600    RRSIG DNAME 7 3 3600 20120311114108 (
                                        20120210114108 60914 example.com.
                                        Bh6S2as2/EjwihXV5FM8hC9urhLMcXCyhXwX
                                        l+/cRM/8Rd0hKZEcoMVN5U8f163hZQgueRA8
                                        J2n8kPSQ3tdEURCkaYdvgU332pJgBpaibWYu
                                        KrkvyPhK/4YkMYkAj245ioHOln8G0wkf6oTW
                                        8dpM5JsAvSAckJ2tK0fBIreM07M= )
justalink                       3600    CNAME onlysig.cname
onlysig.cname                   3600    RRSIG CNAME 7 3 3600 20120311114108 (
                                        20120210114108 60914 example.com.
                                        Bh6S2as2/EjwihXV5FM8hC9urhLMcXCyhXwX
                                        l+/cRM/8Rd0hKZEcoMVN5U8f163hZQgueRA8
                                        J2n8kPSQ3tdEURCkaYdvgU332pJgBpaibWYu
                                        KrkvyPhK/4YkMYkAj245ioHOln8G0wkf6oTW
                                        8dpM5JsAvSAckJ2tK0fBIreM07M= )
cname-a				CNAME	cname-a.cname-b
*.cname-b			A	1.2.3.4
EOF
_enter $BASEDIR/zones
for z in ${ZONES[*]}; do cp $z.zone $z.zone.slave; done
_leave
if ! _knotd_start knot.conf $TIMEOUT; then
	_test_save
	exit 1
fi
_cfg_gen_slave_named ${ZONES[*]} > bind.conf
_ev _named_start bind.conf $TIMEOUT || _progress " * named: started $EVSTR"

# Prepare queries
cat > queries.log << EOF
-t A onlysig.normal.example.com. +dnssec
-t DNAME onlysig.dname.example.com. +dnssec
-t CNAME onlysig.cname.example.com. +dnssec
-t TXT onlysig.normal.example.com. +dnssec
-t CNAME justalink.example.com.
-t RRSIG onlysig.normal.example.com. +dnssec
-t RRSIG onlysig.cname.example.com. +dnssec
-t RRSIG onlysig.dname.example.com. +dnssec
-t A cname-a.example.com.
EOF

# Perform queries
RULES="$BASEDIR/.rules.tmp"
echo -e "warning\t\"[authority].*in rrsig nsec3\"" > $RULES
echo -e "warning\t\"[authority].*in nsec3\"" >> $RULES
_dig_diff_rules $RULES
_dig_both_file knot.conf bind.conf queries.log
_rc $?

_named_stop
_knotd_stop
_test_save
_rc
exit $?
