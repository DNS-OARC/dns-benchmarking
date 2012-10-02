#!/bin/bash
export SIGNKEY=""
export KSK=""
export STYPE="-3"
_keygen() {
	echo -n > keygen.log
        key=$(dnssec-keygen -r /dev/urandom $STYPE -n ZONE -K $BASEDIR $ZONE 2>>keygen.log)
        export SIGNKEY=$BASEDIR/${key}
        key=$(dnssec-keygen $STYPE -f KSK -r /dev/urandom -n ZONE -K $BASEDIR $ZONE 2>>keygen.log)
        export KSK=$BASEDIR/${key}
        echo "\$include $SIGNKEY.key ; ZSK" >> $ZFILE
        echo "\$include $KSK.key ; KSK" >> $ZFILE
}

_sign_zone() {
	flags=""
	if [ "$STYPE" == "-3" ]; then
		flags="$STYPE deadbeef"
	fi
        dnssec-signzone $flags -O full -k ${KSK} -o $ZONE $1 $SIGNKEY.key &>>$LOG
        mv $1.signed $1 &>>$LOG
}

if [ "$(basename $0)" == "sign.sh" ] && [ $# -ge 2 ]; then 
	if [ -z $BASEDIR ]; then
		export BASEDIR=$(pwd)
	fi
	export LOG=.log
	export ZONE=$1
	export ZFILE=$2
	if [ "$3" == "nsec" ]; then
		STYPE=""
	fi
	if [ -f .skey ] && [ -f .ksk ]; then
		export SIGNKEY=$(cat .skey)	
		export KSK=$(cat .ksk)	
	else
		_keygen
		echo $SIGNKEY > .skey
		echo $KSK > .ksk
	fi
	_sign_zone $ZFILE
	cat $LOG
	rm $LOG
fi
