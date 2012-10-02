#!/usr/bin/env bash
source "test.case"

# Config
ZONE="example.com"
[ $# -ge 1 ] && ZONE="$1"
ZONES=( $ZONE $(_generate_names 3) )
NOBODY="nulluser"

# Check for user
if ! sudo -u $NOBODY true &>/dev/null; then
	_progress " * sudo: user '$NOBODY' not exists or cannot sudo it without password"
	exit 1
fi

# Compile zones as different user
_knotd_memcheck_limits 32 0 # getpwnam() leaks, but that can't be fixed, as it's libc internal
_rc_init
_cfg_gen_master ${ZONES[*]} > knot.conf
#echo -e "\nsystem {\nuser \"$USER\";\n}" >> knot.conf
_generate_zones ${ZONES[*]}
if _run_as $NOBODY $KNOTC -c knot.conf compile; then
	_progress " * knotc: allowed to compiled zones without permissions, FAILED"
	_rc 1
else
	_verbose && _progress " * knotc: refused to compile zones without permissions, OK"
fi

# Start
if _knotd_start knot.conf $TIMEOUT; then
	# Reload as different user
	if _run_as $NOBODY $KNOTC -c knot.conf reload; then
		_progress " * knotc: allowed to reload server without permissions, FAILED"
		_rc 1
	else
		_verbose && _progress " * knotc: refused to reload server without permissions, OK"
	fi
	_knotd_reload knot.conf && _verbose && _progress " * knotd: as owner, reloaded OK"
	_knotd_stop
else
	_rc 1
fi


_test_save
_rc
exit $?
