#!/bin/bash

# Original base
diffs=()
if [ $# -lt 2 ]; then
	cd wd
	orig=$(ls *.zone)
	diffs=( $(ls *.zone.*) )
	cp $orig ../
else
	orig=$1
	shift 1
	diffs=$*
	echo "base: $orig"
fi

# Make diffs
prev=$orig
i=0
for f in ${diffs[*]}; do 
	echo "making $i.diff ($prev -> $f)"
	diff -u $prev $f > $i.diff 
	if [ $# -lt 2 ]; then
		mv $i.diff ../
	fi
	(( i += 1 ))
	prev=$f
done

