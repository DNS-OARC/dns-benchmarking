#!/usr/bin/env bash
source "test.case"
if [ -z $KNOT_BRANCH ]; then
	if [ -d $BASEDIR/knot ]; then
		_enter $BASEDIR/knot
		export KNOT_BRANCH=$(git branch -l|grep "*"|awk '{print $2}')
		_leave
	else
		export KNOT_BRANCH="development"
	fi
fi

export MEMPROF_DIR="$CACHE_DIR/memprofile"
[ ! -d $MEMPROF_DIR ] && mkdir -p $MEMPROF_DIR

_progress "Tracking memory usage"
oldpid=$(pidof valgrind.bin knotd named|tr " " ",")
if [ ! -z $oldpid ]; then
        _progress " * couldn't measure memory, daemons already running (PIDs $oldpid)"
	_rc 1
else
        ( memprof.sh $KNOT_BRANCH $MEMPROF_DIR &>/dev/null ); ret=$?
	if [ $ret -ne 0 ]; then
		_progress " * failed with error code $ret"
		exit $ret
	fi
        memplot.sh png top $MEMPROF_DIR/*data; _rc $?
	[ ! -d $BASEDIR/graphs ] && mkdir $BASEDIR/graphs
	[ -e mplot.png ] && mv mplot.png $BASEDIR/graphs/
        cp $MEMPROF_DIR/*.log $BASEDIR/ &>/dev/null

	# Make some statistics
        stats=$(tail -n 1 $(ls -w 1 -c $MEMPROF_DIR/*.data|head -n 1)|awk '{print $4,$5}')
        mean=$(echo $stats|cut -d\  -f1)
        max=$(echo $stats|cut -d\  -f2)
        _progress " * mean usage: $(( mean / (1024*1024) ))MB max: $(( max / (1024*1024) ))MB"
fi

_test_save
_rc
exit $?
