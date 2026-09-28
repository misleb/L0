#!/bin/sh
# array_paths.sh EXE -- Dijkstra over arrays answers every query as
# Floyd-Warshall in awk does, on a generated graph, and neither building the
# graph nor any query copied an array: L0_ARRAY_STATS reports no copies.
set -eu
exe=$1
d=$(mktemp -d "$(dirname "$exe")/array_paths.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "$*"; exit 1; }

# 60 nodes, 400 edges, then 200 queries, some unreachable since a few nodes
# only have edges out.
awk 'BEGIN { s = 11; N = 60
        for (i = 0; i < 400; i++) {
            s = (s * 1103515245 + 12345) % 2147483648; a = s % N
            s = (s * 1103515245 + 12345) % 2147483648; b = s % (N - 5)
            s = (s * 1103515245 + 12345) % 2147483648; w = s % 100
            print "n" a " n" b " " w }
        for (i = 0; i < 200; i++) {
            s = (s * 1103515245 + 12345) % 2147483648; a = s % N
            s = (s * 1103515245 + 12345) % 2147483648; b = s % N
            print "n" a " n" b } }' > "$d/in"

awk 'NF == 3 { a = $1; b = $2; seen[a] = 1; seen[b] = 1
               if (!((a, b) in dist) || $3 < dist[a, b]) dist[a, b] = $3; next }
     NF == 2 { q[++nq] = $1 " " $2 }
     END {
        for (k in seen) for (i in seen) if ((i, k) in dist)
            for (j in seen) if ((k, j) in dist) {
                x = dist[i, k] + dist[k, j]
                if (!((i, j) in dist) || x < dist[i, j]) dist[i, j] = x }
        for (n = 1; n <= nq; n++) { split(q[n], p, " ")
            if (p[1] == p[2]) print 0
            else if ((p[1], p[2]) in dist) print dist[p[1], p[2]]
            else print "unreachable" } }' "$d/in" > "$d/want"

L0_ARRAY_STATS=1 "$exe" < "$d/in" > "$d/out" 2> "$d/err" ||
    fail "exited $?: $(cat "$d/err")"
cmp -s "$d/out" "$d/want" || fail "answers differ from Floyd-Warshall: $(diff "$d/want" "$d/out" | head -5)"
grep -qx 'l0: array copies: 0' "$d/err" ||
    fail "an update copied: $(cat "$d/err")"
