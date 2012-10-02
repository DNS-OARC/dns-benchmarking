#!/usr/bin/env bash
source "test.case"

ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
_rc_init
_cfg_gen_master_named $ZONE > bind.conf
_cfg_gen_slave $ZONE > knot.conf
_generate_zone $ZONE 50000
_named_start bind.conf $TIMEOUT
_knotd_start knot.conf $TIMEOUT
if _rc; then
	sleep 1
	_progress " * named: killing PID=$NAMED_PID"
	kill -9 $NAMED_PID &>>$LOG
	_progress " * named: killed PID=$NAMED_PID"
	sleep 10 
fi
_knotd_stop
_test_save

_rc
exit $?
