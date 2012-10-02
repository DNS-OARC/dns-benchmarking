#!/usr/bin/env bash
source "test.case"

#TODO   +unittests-libknot-realdata\
#TODO   +unittests-zcompile\
#TODO   +unittests-libknot\
for utest in \
        unittests\
        ;
do
	$utest &>>$LOG
	if [ $? -ne 0 ]; then
		_rc $?	
		_progress " * unit test '$utest' failed with error code $?"
	fi
done

# Digs
_test_save
_rc
exit $?
