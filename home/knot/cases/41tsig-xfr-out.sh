#!/usr/bin/env bash
source "test.case"

key=$(_rnd_str 10)
secret=$(_rnd_str 10|base64)
_tsig_use "$key" "hmac-md5" "$secret"
_dig_param "-y $key:$secret"

. 21ixfr-out.sh
