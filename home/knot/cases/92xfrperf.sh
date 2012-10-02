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

export XFRPROF_DIR="$CACHE_DIR/performance"
[ ! -d $XFRPROF_DIR ] && mkdir -p $XFRPROF_DIR

_progress "Tracking XFR performance"
cd $BASEDIR
oldpid=$(pidof valgrind.bin knotd named|tr " " ",")
if [ ! -z $oldpid ]; then
        _progress " ( couldn't measure XFR perf, daemons already running (PIDs $oldpid)"
else
        ( perf-xfr.sh $KNOT_BRANCH $XFRPROF_DIR &>perf.log ); ret=$?
	if [ $ret -ne 0 ]; then
                _progress " * perf-xfr.sh failed with error code $ret"
		_test_save
                exit $ret
        fi

        ( perf-xfr-plot.sh png ); _rc $?
        cat perf.log|while read l; do _progress "$l"; done

	cp $XFRPROF_DIR/*.log $BASEDIR/; cd $BASEDIR
        [ ! -d $BASEDIR/graphs ] && mkdir -p $BASEDIR/graphs
        mv $BASEDIR/*.png $BASEDIR/graphs/
fi

_test_save
_rc
exit $?
