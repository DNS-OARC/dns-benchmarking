#!/usr/bin/env bash
source "test.case"

if [ $# -lt 1 ]; then
	ret=0
	for t in $(dirname $0)/ixfrs/*; do	
		if [ -d $t ]; then
			name=$(basename $t)
			_progress "* Running IXFR scenario: $name"
			$0 $name
			(( ret |= $? ))
		fi
	done
	[ -d "ixfr-scenarios" ] && mv "ixfr-scenarios" "23ixfr-in-integrity"
	exit $ret
fi

# Prepare scenario
ROLE=$(dirname $0)/ixfrs/$1
BASE=$(ls $ROLE/*.zone)
ZONE=$(basename $BASE)
ZONE=${ZONE%%.zone};

# Load changes
CHID=0
DIGID=""
CHANGES=( $(ls $ROLE/*.diff) )
CHANGES_C=${#CHANGES[*]}
ZONES_GEN=( $(_generate_names 4) )
ZONES_GEN=() #TMP
ZONES=( $ZONE ${ZONES_GEN[*]} )
export TIMEOUT=300
export DIG_FULL_LOG=1 # full dig logging
_rc_init
_cfg_gen_master_named ${ZONES[*]} > bind.conf
_cfg_gen_slave ${ZONES[*]} > knot.conf
_generate_zones_size 100 200
_generate_zones ${ZONES_GEN[*]}
cp $BASE $BASEDIR/zones/ &>>$LOG
_named_start bind.conf $TIMEOUT
_knotd_bin "unittests-xfr -z $ZONE"
_knotd_start knot.conf $TIMEOUT
_rc && _knotd_wait_axfr ${ZONES[*]}
if [ -f $ROLE/base.dig ]; then
	_verbose && _progress " * zones: digging '$(cat $ROLE/base.dig)' after bootstrap"
	_dig_both_file knot.conf bind.conf $ROLE/base.dig
fi
ret=$?; while [ $ret -eq 0 ] && [ $CHID -lt $CHANGES_C ]; do
	# Update generated zones
        updated=( $(_arr_selection ${ZONES_GEN[*]}) )
	updated=() #Tmp
        _generate_zones_update ${updated[*]}
	# Patch observed zone
	_enter $BASEDIR/zones
	_verbose && _progress " * zones: applying '$(basename ${CHANGES[$CHID]})' to '$ZONE'"
        # Apply patch
        patch -p1 $ZONE.zone ${CHANGES[$CHID]} >> $LOG || _progress " * zones: failed to apply ${CHANGES[$CHID]}"
	touch $ZONE.zone
	sleep 2
	_leave
        # Dig it
        DIGID=${CHANGES[$CHID]}; DIGID=${DIGID%%.diff}; DIGID=${DIGID}.dig
        (( CHID += 1 ))	
	# Wait for IXFR/IN
        _named_reload
        _knotd_wait_ixfr ${updated[*]} $ZONE
	# Integrity check
	[ -f $ROLE/nointegrity ] || _knotd_check_integrity
	# Dig if any queries specified
	if [ -f $DIGID ]; then
		_dig_both_file knot.conf bind.conf $DIGID
	fi
	# Check if still alive
	kill -0 $KNOTD_PID &>/dev/null;
	if [ $? -gt 0 ]; then 
		_progress " * knotd: crash detected, refusing to continue tests"
		CHID=$CHANGES_C
		_rc 1
	fi
done
if _rc; then
	export DIG_FULL_LOG=0 # disable full dig logging
	_dig_fetch_many knot.conf bind.conf ${ZONES[*]}
	_rc $?
fi
_knotd_stop
_named_stop
_test_save
_enter $BASEDIR
[ ! -d "ixfr-scenarios" ] && mkdir ixfr-scenarios
mv "23ixfr-in-integrity" "ixfr-scenarios/$1"
_leave
_rc
exit $?

