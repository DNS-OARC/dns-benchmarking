#!/usr/bin/env bash
source "test.case"
export BASE="???"

# Analyze differences between tested implementations
cd $BASEDIR
export REG_DIR="/var/cache/knot-tests/regressions"
if [ ! -d regressions ]; then
	02compliance.sh --knot
	if [ $? -ne 0 ]; then
		_progress " * compliance tests failed, cannot evaluate regressions against $BASE"
		exit 1
	fi
fi
if [ ! -d $REG_DIR/base ]; then
	_progress " * no stored compliance test to measure regressions against"
	exit 2
fi

# Copy base values 
cd $BASEDIR/regressions
cp $REG_DIR/base/*.pcat .

# Perform regression testing
BASE="$(cat $REG_DIR/base/info)"
TARGET=$(_knotd_rev)
if [ "$TARGET" != "" ]; then
        TARGET="$(_knotd_ver)-git.$TARGET"
else
	TARGET="latest"
fi

mv signed-base.pcat signed-$BASE.pcat
mv unsigned-base.pcat unsigned-$BASE.pcat
cp signed-knotd.pcat signed-$TARGET.pcat
cp unsigned-knotd.pcat unsigned-$TARGET.pcat
_pcat_cmp "signed-$BASE.pcat" "signed-$TARGET.pcat" "signed-regressions.log"
_pcat_cmp "unsigned-$BASE.pcat" "unsigned-$TARGET.pcat" "unsigned-regressions.log"

# Store graphs
[ ! -d $BASEDIR/graphs ] && mkdir $BASEDIR/graphs
adiff-g.sh png unsigned-$BASE.pcat unsigned-knotd.pcat &>>$LOG; mv adiff.png $BASEDIR/graphs/unsigned-regressions.png
adiff-g.sh png signed-$BASE.pcat signed-knotd.pcat  &>>$LOG; mv adiff.png $BASEDIR/graphs/signed-regressions.png


cd $BASEDIR
_test_save
_rc
exit $?
