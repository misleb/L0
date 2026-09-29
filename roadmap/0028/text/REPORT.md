# 0028 text at scale: wordfreq, json, sort with arrays

All three work, pass their tests under `L0_RC_CHECK`, match their references
byte for byte on the full-size inputs, and copy no array (`L0_ARRAY_STATS`:
0 copies in each). All three are faster than 0014's versions rebuilt today.
wordfreq also beats 0014 on memory, and json roughly halves 0014's memory.
json and sort still need about 25 bytes of memory per input byte. That is
not from parsing or sorting: it is reading input of unknown length into an
`(array int)`. That is limit 01, and it earns 0026.

## Results

Second of two runs, peak RSS from `/usr/bin/time -l` (which needs to run
outside the sandbox: `sysctl kern.clockrate` is denied inside it). 0014's
programs are rebuilt with today's compiler. Their READMEs' figures are
stale, and today they are 2 to 4 times faster than recorded.

| program, input | this | 0014 today | Python 3.14 | other |
|---|---|---|---|---|
| wordfreq, 10 MB, 20 K words | 0.16 s, 10 MB | 0.56 s, 8 MB | 0.29 s, 95 MB | |
| wordfreq, 10 MB, 195 K words | 0.40 s, 54 MB | 1.02 s, 68 MB | 0.41 s, 113 MB | |
| json, 11.5 MB | 0.38 s, 257 MB | 0.68 s, 439 MB | 0.56 s, 111 MB | |
| sort, 10 MB, 171 K lines | 0.26 s, 260 MB | | 0.10 s, 37 MB | `sort` 0.04 s, 22 MB |

Builds take 0.37 to 0.45 s each. Tests: wordfreq 15, json 25, sort 10, all
passing. Each has a property test against an independent implementation or
a round trip.

## Limits, by cost

**01. Holding input bytes: 25 bytes a byte, the same as a list**
(`limits/01-input-into-array.l0`, `hypothetical/01-input-into-array.l0`).
Nothing tells a program its input's length before reading it, so an array
must start small and double. The last doubling holds 2^24 elements (134 MB)
and the 67 MB array it copies at once, and the smaller ones stay resident.
Reading 10 MB peaks at 257 MB doubling, 81.5 MB into an exact-size array
(possible only with the length given as an argument), 241.5 MB as a list,
and 18 MB in Python. json and sort are 257 of their 257 to 260 MB, and scale
at about 22 bytes a byte up to 23 MB. The workaround, 64 K chunks in an
`(array (array int))`, gets sort to 91.5 MB but makes it 60% slower (0.43 s
against 0.27 s), because every byte read becomes two `array_get`s, a `div`,
and a `mod`. The code I would have written reads `(read_all 0)` into a
packed `bytes` of exactly the input's length, with `bytes_len` and
`bytes_get`. The checker says `unknown type bytes` and `unknown function
read_all`. **This earns 0026**, with reading straight into packed bytes as
part of it, as 0026 already suspects.

**02. Short strings as keys: 24 bytes a byte** (`limits/02-word-keys.l0`,
`hypothetical/02-word-keys.l0`). wordfreq's 195,412 keys are 36.8 MB of its
54 MB peak. Holding them alone: 40.2 MB as lists, 20.7 MB as one `(array
int)` per word (a malloc'd block of about 80 bytes for the average 7.8
letters), and 1.5 MB of letters if packed. This supports 0026 but would not
earn it alone: wordfreq already beats 0014 and Python on memory.

**03. No floating point** (`limits/03-no-floats.l0`,
`hypothetical/03-no-floats.l0`). json cannot print `1.50` as `1.5` or `1E5`
as `100000.0`, as `json.tool` does, without correctly rounded conversion
from decimal to double and back. With 64-bit integers only, that means
writing bignums in L0 first. json copies such numbers as written. It costs
nothing on the benchmark, which has only integers, but every fraction or
exponent prints differently. The checker says `unknown type float`. This is
not about arrays. It is recorded because it is the one place json's output
cannot match.

## 0025 and 0026

- **0026 is earned** by json and sort (limit 01), and supported by wordfreq
  (limit 02).
- **0025 is not earned by these programs.** None updates an array held in
  another. The only nested arrays are the chunk workaround, where a chunk is
  filled alone before it is stored and only read afterwards, and reading
  through an outer array copies nothing. Arrays inside **data values**
  updated in place: wordfreq's `Table` holds both of its arrays and is
  matched apart and rebuilt for every word, with 0 copies in 2,978,124
  updates. The same goes for `Ranked`, json's and sort's `Input`, and
  `exp/wrap.l0` (0 copies in 200,000). Matching a value that nothing else
  holds releases it (spec 10.3), so its arrays are then held once. A data
  value is how a function returns several arrays, since there are no
  tuples, and it costs nothing.

## Wrong, missing, or ambiguous in the spec and skills

1. **The shipped skill overstates what copies.** `lib/skills/l0-code/SKILL.md`
   says "What copies: ... an array stored inside another array or a data
   value, whose every update copies it". For a data value held once and
   matched apart, that is false (above). Spec 6.5's last sentence is
   accurate, since it says "while the outer value still holds it", but it
   reads the same way. Both should say that matching a data value nothing
   else holds gives its arrays back unshared, and show the match-and-rebuild
   idiom, which is how a function returns several arrays.
2. **Nothing says how to hold input as an array, or what it costs.** The
   skill warns that the input as a list is 2.4 GB per 100 MB and says to
   stream. It does not say that reading into an array, the only other way to
   hold input, costs about the same (limit 01). The skill should say so, and
   show the doubling loop, until 0026 changes it.
3. **A stale diagnostic.** An unknown type gives "a type is int, bool, (list
   T), or a data type, whose name starts uppercase". It leaves out `(array
   T)`.
4. **The repository's l0-code skill** (`.cursor/skills/l0-code/SKILL.md`)
   says "To run a program: `build/l0i run FILE.l0`". The frozen stage-0
   interpreter does not know `(array T)` ("expected a type: int, bool, (list
   T), or a data type name"), so it cannot run any program here. It should
   point at `tools/l0 run`.
5. **A typo in spec 10.3**: "`array_set` consumes its array and its element,
   as any function consumes its arguments A `match` whose subject..." is
   missing a period and reads as one sentence.
6. **Spec 6.5 does not give `array_new`'s cost.** It is linear in n, and
   touches n words at once, which is why doubling has the peak it has. 10.3
   says arrays are malloc'd. 6.5, where a reader looks, says nothing of time
   or memory for creating an array.
7. **0014's recorded measurements are stale** (json 1.9 s and 873 MB is
   0.68 s and 439 MB today; wordfreq 2.13 s is 0.56 s), so a comparison with
   0014 must rebuild and re-measure, not quote.

## A trap worth knowing, not a limit

json's checking pass writes to handle -1, where `put` writes nothing. But
the first version still ran the indentation loop, so checking was quadratic
in nesting depth: 28 s for 100,000 levels, 0.02 s once `newline` returned at
once for no handle. A pass that "does nothing" with its output still pays
for every loop that produces it.

## Files

```
REPORT.md                 this
measure.sh                0014's measure.sh, temporary file kept here
wordfreq/  wordfreq.l0 main.l0 wordfreq_test.l0 reference.py README.md
json/      json.l0 main.l0 json_test.l0 differ.py README.md
           testdata/sample.json testdata/sample.expected
sort/      sort.l0 main.l0 sort_test.l0 gen_lines.py reference.py README.md
limits/    01-input-into-array.l0 02-word-keys.l0 03-no-floats.l0
hypothetical/  01-input-into-array.l0 02-word-keys.l0 03-no-floats.l0
exp/       wrap.l0 (data-held arrays update in place), stage.l0 (sort's time
           by stage), sort_chunks.l0 (the chunk workaround in full)
data/      inputs: gen.py 10 20000 1, gen.py 10 500000 2, gen_big.py 100000,
           gen_lines.py 10; all regenerate deterministically
base/      0014's wordfreq and json, rebuilt
```
