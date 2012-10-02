#!/usr/bin/env bash
BASEDIR=$(pwd)
REMOTE="player"
REMOTE1="listener"
ADDRESS="192.168.1.10"
PORT="53531"
ZONE="$1"
ZFILE="$ZONE.zone"
ZFILE_RUN=".run.zonefile"
CONF_RUN=".run.conf"
NSD4D="$BASEDIR/nsd4"
THREADS=1
LOG="benchmark.log"
DATA="benchmark.data"
RESPONSES_MAX=200000
USER=$(whoami)
RUNNING=""
PID=0
_seq="gseq"
which $_seq &>/dev/null || _seq="seq"

echo -n > $LOG

function _prepare() { # prepare zonefile (origin, zonefile, server={knotd|named})
	echo "# preparing zone: $1 for $3 ($THREADS workers)"
	ln -fs $2 $ZFILE_RUN
	rules="s%@ZONEFILE@%$ZFILE_RUN%g"
	rules="$rules;s%@BASEDIR@%$BASEDIR%g"
	rules="$rules;s%@THREADS@%$THREADS%g"
	rules="$rules;s%@ADDRESS@%$ADDRESS%g"
	rules="$rules;s%@PORT@%$PORT%g"
	rules="$rules;s%@USER@%$USER%g"
	rules="$rules;s%@ZONE@%$1%g"
	sed "$rules" $3.conf > $CONF_RUN
	if [ "$3" == "knotd" ]; then
		echo "# compiling zone for knotd"
		knotc -c $CONF_RUN compile >>$LOG 2>>$LOG
	fi
	if [ "$3" == "nsd" ]; then
		if [ ! -f "$BASEDIR/wd/nsd.db" ]; then
		echo "# compiling zone for nsd"
		nsdc -c $CONF_RUN rebuild >>$LOG 2>>$LOG
		fi
	fi
}

function _cleanup() { # cleanup temporary files
	#rm $ZFILE_RUN >>$LOG 2>>$LOG
	rm $CONF_RUN >>$LOG 2>>$LOG
}

function _start() { # start server and return PID

	# set parameters and server started pattern echo "# starting $1"
	params="-c $CONF_RUN";
	match="PID stored in"
	if [ "$server" == "named" ]; then
		params="$params -g -n $THREADS";
		match="sending notifies"
	fi
	if [ "$server" == "yadifad" ]; then
		match="ready to work"
	fi

	if [ "$1" == "nsd" ]; then
		echo -n > server.log
		nsdc -c $CONF_RUN start	>>$LOG 2>>$LOG
		started=0
		while [ $started -eq 0 ]; do
			sleep 1
			started=$(grep "nsd started" server.log|wc -l)
		done
	elif [ "$1" == "nsd4" ]; then
		OLDPATH="$PATH"
		export PATH="$NSD4D:$PATH"
		echo -n > server.log
		$NSD4D/nsd-control -c $CONF_RUN start 2>&1 >> $LOG
		started=0
		while [ $started -eq 0 ]; do
                        sleep 1
                        started=$(grep "nsd started" server.log|wc -l)
                done
		export PATH="$OLDPATH"
	else
		$1 $params &>server.log &
		PID=$!
        	started=0	
		while [ $started -eq 0 ]; do
			sleep 1
			mlines=$(grep "$match" server.log|wc -l)
			if [ $mlines -gt 0 ]; then
				echo "# * $1 started, PID=$PID"
				started=1		
			fi
		done
	fi

	RUNNING="$1"
}

function _stop() { # stop server
	if [ "$RUNNING" == "nsd" ]; then
		nsdc -c $CONF_RUN stop >>$LOG 2>>$LOG
                stopped=0
                while [ $stopped -eq 0 ]; do
                        sleep 1
                        stopped=$(grep "shutting down" server.log|wc -l)
                done
		cat server.log >> $LOG
		rm server.log
	elif [ "$RUNNING" == "nsd4" ]; then
                OLDPATH="$PATH"
                export PATH="$NSD4D:$PATH"
	        $NSD4D/nsd-control -c $CONF_RUN stop 2>&1 >> $LOG
                stopped=0
                while [ $stopped -eq 0 ]; do
                        sleep 1
                        stopped=$(grep "shutting down" server.log|wc -l)
                done
                cat server.log >> $LOG
                rm server.log	
                export PATH="$OLDPATH"
	else
		kill $1
		wait $1
		cat server.log >> $LOG
		rm server.log
		echo "# stopped PID=$1"	
	fi

	RUNNING=""
}

function _perftest() {
	prefix0=""
	if [ ! -z $REMOTE ]; then
		scp $1.perf $REMOTE: >>$LOG 2>>$LOG
		prefix0="ssh $REMOTE"
	fi
	prefix1=""
	if [ ! -z $REMOTE1 ]; then
                scp $1.perf $REMOTE1: >>$LOG 2>>$LOG
                prefix1="ssh $REMOTE1"
	else
		prefix1=$prefix0
        fi
	_dnsp0="$prefix0 dnsperf -s $ADDRESS -p $PORT -d $1.perf -l 20"
	_dnsp1="$prefix1 dnsperf -s $ADDRESS -p $PORT -d $1.perf -l 20"
       (for i in $(seq 1 3); do $_dnsp0 & $_dnsp0 & $_dnsp0 & $_dnsp0; sleep 5; done)|tee perf.log|grep "Queries per second"|awk '{print $4}'|R --slave -e "d <- scan(file('stdin'),quiet=TRUE); mean(d) * 4;"|cut -d\  -f2
}

function _benchmark() { # benchmark server (server={knotd|named}, origin, threads), returns: number of qps
	# prepare
	server=$1	
	origin=$2
	zonefile=$2.zone
	THREADS=$3
	_prepare "$origin" "$zonefile" "$server"

	# wait for start
	_start $server
	echo "# measuring performance"
	qps=$(_perftest $origin)
	echo $qps >> $DATA
	echo "# $server with '$origin' finished with $qps q/s"
	_stop $PID

	# remove temporary files
	_cleanup
}

function _responses() { # measure responses
	rate=$1
	tracefile=$2

	(ssh $REMOTE sh -c "cd;cd testlab;rm -rf results &>/dev/null; ./bin/run_test -s nostart -t $tracefile -p $rate" 2>&1) &>responses.log
	echo $(cat responses.log|grep Rated|awk '{print $15}') $(cat responses.log|grep "packets captured"|awk '{print $1}')
}

function _benchmark_ploss() { # benchmark server (server={knotd|named}, origin, from, step, to), returns: number of responses
	# prepare
	server=$1	
	origin=$2
	zonefile=$2.zone
	from=$3
	step=$4
	to=$5
	tfile="cznic-bench"
	_prepare "$origin" "$zonefile" "$server"

	# wait for start
	_start $server
	for rate in $($_seq $from $step $to); do
		echo "# measuring answer rate for $rate pps"
		r1=( $(_responses $rate $tfile) )
		r2=( $(_responses $rate $tfile) )
		r3=( $(_responses $rate $tfile) )
		responses=$(echo "scale=0;(${r1[1]}+${r2[1]}+${r3[1]})/3.000"|bc 2>/dev/null)
		arate=$(echo "scale=3;(${r1[0]}+${r2[0]}+${r3[0]})/3.000"|bc 2>/dev/null)
		ploss=$(echo "scale=3; ($responses / $RESPONSES_MAX)*100.0"|bc 2>/dev/null)
		echo "# * $responses responses, ${ploss}% answer rate for $rate (actual $arate) pps"
		echo -e "$arate\t$ploss" >> $DATA
	done
	rt=( $(_responses 0 "cznic-bench-top") )
	responses=${rt[1]}
	arate=${rt[0]}
	rate="top"
	ploss=$(echo "scale=3; ($responses / $RESPONSES_MAX)*100.0"|bc 2>/dev/null)
	echo "# measuring answer rate for $rate pps"
	echo "# * $responses responses, ${ploss}% answer rate for $rate (actual $arate) pps"
	echo -e "$arate\t$ploss" >> $DATA
	echo "# $server with '$origin' finished measuring packet loss"
	_stop $PID

	# remove temporary files
	_cleanup
}

function _idstr() { # return id string
	[ "$1" == "nsd" ] && echo "nsd-$(nsd -v 2>&1|head -n 1|awk '{print $3}')"
	[ "$1" == "nsd4" ] && echo "nsd-$($NSD4D/nsd --help 2>&1|tail -n 1|awk '{ print $2 }')"
	[ "$1" == "knotd" ] && echo "knotd-$(knotd -V|awk '{print $4}')"
	[ "$1" == "named" ] && echo "named-$(named -V|head -n1|awk '{print $2}')"
	[ "$1" == "yadifad" ] && echo "yadifa-1.0.0"
}

# Benchmarks - threads
rm $BASEDIR/wd/* 2>>$LOG
REMOTE="player"
TFROM=1
TTO=6

#export PATH="$HOME/nsd-trunk:$PATH"
DATA="nsd-threads.data"
echo "# $(_idstr nsd) $ZONE threads={${TFROM}..${TTO}}" > $DATA
for i in $($_seq $TFROM $TTO); do
	echo -en "$i\t" >> $DATA
	_benchmark nsd $ZONE $i
done

DATA="knotd-threads.data"
echo "# $(_idstr knotd) $ZONE threads={${TFROM}..${TTO}}" > $DATA
for i in $($_seq $TFROM $TTO); do
	echo -en "$i\t" >> $DATA
	_benchmark knotd $ZONE $i
done

DATA="yadifa-threads.data"
echo "# $(_idstr yadifad) $ZONE threads={${TFROM}..${TTO}}" > $DATA
for i in $($_seq $TFROM $TTO); do
	echo -en "$i\t" >> $DATA
	_benchmark yadifad $ZONE $i
done

#export PATH="$HOME/nsd-trunk:$PATH"
#DATA="nsd4-threads.data"
#echo "# $(_idstr nsd4) $ZONE threads={${TFROM}..${TTO}}" > $DATA
#for i in $($_seq $TFROM $TTO); do
#	echo -en "$i\t" >> $DATA
#	_benchmark nsd4 $ZONE $i
#done


# Benchmarks - packet loss
REMOTE="player"
THREADS=4
rate_begin=25000
rate_step=25000
rate_end=300000
for s in named knotd nsd yadifad; do
	DATA="$s-ploss.data"
	echo "# $(_idstr $s) $ZONE packet loss with rate <$rate_begin, $rate_end>" > $DATA
	_benchmark_ploss $s $ZONE $rate_begin $rate_step $rate_end 
done
exit 1
