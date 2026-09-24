#!/bin/sh
# Summarise, for an assembly file, every call site that targets an L0
# function (_l0_f_* or _l0_p_*): "bl" is a real call that grows the stack,
# "b" is a jump that does not. Prints one line per call site as
#   caller -> callee  kind
#
# Usage: experiments/tailcalls/callsites.sh FILE.s [FILTER_REGEX]
set -eu
awk -v filt="${2:-.}" '
/^_l0_[fp]_[A-Za-z0-9_]*:/ { fn = substr($1, 1, length($1) - 1); next }
/^_[A-Za-z0-9_]*:/ { fn = substr($1, 1, length($1) - 1); next }
$1 == "bl" && $2 ~ /^_l0_[fp]_/ { if (fn ~ filt) print fn " -> " $2 "  bl (call)" }
$1 == "b"  && $2 ~ /^_l0_[fp]_/ { if (fn ~ filt) print fn " -> " $2 "  b (jump)" }
' "$1" | sort | uniq -c
