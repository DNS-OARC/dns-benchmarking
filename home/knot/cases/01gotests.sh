#!/usr/bin/env bash
source "test.case"
export ENABLE_GO="yes"

if [ -z "$GOROOT" ]; then
        # attempt to derive GOROOT from Go binaries iff in PATH
        GC=6g
        GL=6l
        XG=$(which $GC) || true
        if [ -z "$XG" ]; then
                GC=8g
                GL=8l
                XG=$(which $GC) || true
        fi
        if [ -z "$XG" ]; then
                _progress " * GOROOT not set and Go tools not found in PATH"
		exit 1
        fi
        GOBIN=$(dirname $XG)
        GC=$GOBIN/$GC
        GL=$GOBIN/$GL
        cd $BASEDIR
        cat > main.go <<EOF
package main
import ("runtime"; "fmt")
func main() {
        fmt.Println(runtime.GOROOT())
}
EOF
        $GC -o main.o main.go &>> $LOG
        $GL -o main main.o &>> $LOG
        GOROOT=$(./main)
	if [ $? -ne 0 ]; then
		 _progress " * derivation of GOROOT failed"
		exit 1
	fi
fi

export GOROOT

# 4. Prepare and run gotests ===================================================
_getpkg() { # pkg
        pdir=$(pwd)
        #_progress " - $(basename $1)"
        cd $GOROOT/src/pkg/cznic
        if [ ! -d $1 ]; then
                bname=$(basename $1)
                git clone git://git.nic.cz/go/$bname $1 &>>$LOG
		if [ $? -ne 0 ]; then
                        _progress " * git clone git://git.nic.cz/go/$bname failed"
			_rc 1
		fi
        else
                cd $1
                git pull &>>$LOG
		if [ $? -ne 0 ]; then
			_progress " * git pull of $GOROOT/src/pkg/cznic/$1 failed"
			_rc 1
		fi
                cd $GOROOT/src/pkg/cznic
        fi

        cd $1
        make install &>>$LOG
	if [ $? -ne 0 ]; then
		_progress " * make install $GOROOT/src/pkg/cznic/$1 failed"
		_rc 1
	fi
        cd $pdir
}

_mkpkg() { # pkg
        #_progress " - $(basename $1)"
	ret=0
        pdir=$(pwd)
        cd $GOROOT/src/pkg/cznic/$1
        make install &>>$LOG; ret=$?
	[ $ret -ne 0 ] && _progress " * make install $GOROOT/src/pkg/cznic/$1 failed"
        cd $pdir
	return $ret
}

# Fetch Go packages
GOTEST=$(which knot-gotest)
if [ ! -z "$ENABLE_GO" ] && [ -z $GOTEST ]; then
_verbe && _progress " * fetching packages required by knot-gotests"
export PATH=$GOROOT/bin:$PATH
if [ ! -d $GOROOT/src/pkg/cznic ]; then
        mkdir -p  $GOROOT/src/pkg/cznic &>>$LOG
fi

for pkg in \
        lexer\
        lex\
        ../../cmd/golex\
        fileutil\
        fileutil/storage\
        fileutil/falloc\
        fileutil/hdb\
        strutil\
        rnd\
        dns\
        ;
        do _getpkg $pkg ;
done

_verb && _progress " * building packages required by knot-gotests"
for pkg in \
        lexer\
        lex\
        ../../cmd/golex\
        fileutil\
        fileutil/storage\
        fileutil/falloc\
        fileutil/hdb\
        strutil\
        rnd\
        dns\
        dns/rr\
        dns/zone\
        dns/msg\
        dns/xfr\
        dns/cache\
        dns/hosts\
        dns/named\
        dns/resolv\
        dns/resolver\
        dns/zdb\
        ;
        do _mkpkg $pkg ;
done

#TODO- after getting rid of this external dependency
_verb && _progress " * fetching external Go packages"
goinstall -dashboard=false github.com/miekg/godns &>>$LOG
if [ $? -ne 0 ]; then
	_progress  " * goinstall: failed"
	_rc 1
fi

# Install knot-gotests
_verb && _progress " * compiling knot-gotests"
cd $BASEDIR
git clone git://git.nic.cz/knot-gotests &>>$LOG
if [ $? -ne 0 ]; then
        _progress " * failed to clone repository"
	exit 1
fi
cd knot-gotests
./make.sh &>>$LOG
if [ $? -ne 0 ]; then _progress " * make.sh failed"; exit 1; fi

fi

# 5. Run knot-gotests ==========================================================
if [ -f $GOTEST ] && [ ! -z "$ENABLE_GO" ]; then
        _progress " * running knot-gotest (default domain)"
        $GOTEST &>gotest.log
        grep -o -E "ERROR:(.*)$" gotest.log|while read l; do
                l=${l/ERROR: }
                _progress "   * $l"
        done
        errs=$(grep -o -E "ERROR:(.*)$" gotest.log|wc -l)
        if [ $errs -gt 0 ]; then _progress "   --> $errs failures (default domain)"; _rc 1; fi
        cat gotest.log >> $LOG
        # issue 268
        _progress " * running knot-gotest (root domain)"
        $GOTEST -zone="." &>gotest.log || true
        grep -o -E "ERROR:(.*)$" gotest.log|while read l; do
                l=${l/ERROR: }
                _progress "   * $l"
                (( errs += 1 ))
        done
        errs=$(grep -o -E "ERROR:(.*)$" gotest.log|wc -l)
        if [ $errs -gt 0 ]; then _progress "   --> $errs failures (root domain)"; _rc 1; fi
        cat gotest.log >> $LOG
        rm gotest.log
fi

[ -d $BASEDIR/knot-gotests ] && rm -rf $BASEDIR/knot-gotests
_test_save
_rc
exit $?
