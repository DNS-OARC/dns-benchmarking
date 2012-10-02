#!/usr/bin/env bash
origin=$1
zf=$2
if [ $# -ne 2 ]; then
	echo "Usage: $0 <origin> <zonefile>"
	exit 1
fi

# Covered types
types=( \
        "A"  "AAAA" "NS" "MX" "DNAME" "CNAME" \
        "TXT" "SRV" "WKS" "PTR" \
        "HINFO" "RP" "AFSDB" \
        )
# SPF, KEY, DHCID, PX, KX, IPSECKEY, SSHFP, APL, NSAP, RT, X25, LOC, ISDN - Not supported in Scapy

# Evalute type candidate names
for t in ${types[@]}; do
	name=$(grep -m 10 -E "(IN | )$t[ \t]" "$zf"|sort -R|head -n 1|awk '{print $1}')
	if [ "$name" != "" ]; then
		[ "$name" == "@" ] && name="$origin."
		[ ${name#${name%?}} != "." ] && name="$name.$origin."
		echo $name $t	
	#else
		#echo $t
	fi
done
