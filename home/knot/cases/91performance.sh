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

export DNSPROF_DIR="$CACHE_DIR/performance"
[ ! -d $DNSPROF_DIR ] && mkdir -p $DNSPROF_DIR

_progress "Tracking UDP performance"
cd $BASEDIR
oldpid=$(pidof valgrind.bin knotd named|tr " " ",")
if [ ! -z $oldpid ]; then
        _progress " * couldn't measure UDP perf, daemons already running (PIDs $oldpid)"
	_rc 1
else
        ( dnsprof.sh $KNOT_BRANCH $DNSPROF_DIR &>dnsprof.log ); ret=$?
	if [ $ret -ne 0 ]; then
		_progress " * dnsprof.sh failed with error code $ret"
		exit $ret
	fi
	
        ( profplot.sh png $DNSPROF_DIR/dnsprof.data )
	cat dnsprof.log|while read l; do _progress "$l"; done
	cp $DNSPROF_DIR/*.log $BASEDIR/; cd $BASEDIR
	[ ! -d $BASEDIR/graphs ] && mkdir -p $BASEDIR/graphs
	mv $BASEDIR/*.png $BASEDIR/graphs/
fi

_test_save
_rc
exit $?
