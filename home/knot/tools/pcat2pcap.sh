#!/bin/sh
tf=$1.tmp
df=$1.tr
awk -W posix '
BEGIN { RS="" }
{
	if (length($2) >= 4096*2)
		printf "%.*s", 4096*2, $2;
	else {
		printf "%*s", length($2), $2;
		printf "%0*d", 4096*2-length($2), 0;
	}
	if (length($3) >= 4096*2)
		printf "%.*s", 4096*2, $3;
	else {
		printf "%*s", length($3), $3;
		printf "%0*d", 4096*2-length($3), 0;
	}
}' $1 > $tf.1
xxd -p -r $tf.1|od -Ax -tx1 -v > $tf.2
text2pcap -m 4096 -u 53,10000 $tf.2 $df
rm $tf.1
rm $tf.2
echo "Saved pcap trace in $df"


