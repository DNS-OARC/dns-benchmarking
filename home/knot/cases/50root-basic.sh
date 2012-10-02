#!/usr/bin/env bash
source "test.case"

_save_prev() {
	_enter $BASEDIR
	mv $1 _$1 2>>$LOG
	_leave
}

_save_swap() {
	_enter $BASEDIR
	mv $1 "$2" 2>>$LOG
	mv _$1 $1 2>>$LOG
	_leave
}

_chk_results() {
	if [ $1 -ne 0 ]; then
		_progress " * last test failed, skipping others";	
		exit $1;
	fi
}

cmp_ret=0

# AXFR
_progress " * Testing AXFR on root zone"
_save_prev "11axfr-in"
11axfr-in.sh .
_rc $?
_save_swap "11axfr-in" "50root-axfrin"
_chk_results $cmp_ret

# IXFR/IN
_progress " * Testing IXFR/IN on root zone"
_save_prev "20ixfr-in"
20ixfr-in.sh .
_rc $?
_save_swap "20ixfr-in" "50root-ixfrin"
_chk_results $cmp_ret

# IXFR/OUT
_progress " * Testing IXFR/OUT on root zone"
_save_prev "21ixfr-out"
21ixfr-out.sh .
_rc $?
_save_swap "21ixfr-out" "50root-ixfrout"
_chk_results $cmp_ret

_rc
exit $?
