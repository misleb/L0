# Tail-call experiments for roadmap item 0011

Measurements behind the 0011 recommendation: what happens to L0 tail calls
today at each optimisation level, and what each way of guaranteeing them
costs. Nothing here changes the compiler, runtime, or spec. Each option is
prototyped as a rewrite of IR the current compiler emitted (`tailify.py`),
which stands in for the corresponding change to `compiler/emit.l0`.

Measured on macOS arm64 with Homebrew clang 23.1.1 (what `tools/l0ll` uses)
and Apple clang 21, against the compiler at commit 12a1282, before roadmap
item 0015 guaranteed tail calls. The worker ran these from
`experiments/tailcalls/`, and the scripts still name that directory; they
were copied here as the record, and `report.md` is its final report.

## Reproducing

From the repository root, after `tools/build.sh`, `tools/bootstrap.sh` and
`cp build/stage2 build/l0c-native`:

```sh
experiments/tailcalls/build_cases.sh    # emit and link every case, -O0/-O1/-O2
experiments/tailcalls/matrix.sh         # results/baseline_depth.txt
experiments/tailcalls/build_protos.sh   # build every prototype option
experiments/tailcalls/proto_matrix.sh   # results/proto_depth.txt (slow, ~10 min)
experiments/tailcalls/compiler_test.sh  # results/compiler.txt
experiments/tailcalls/pad_test.sh       # results/pad.txt
experiments/tailcalls/nested_test.sh    # results/nested.txt
experiments/tailcalls/rc_check.sh       # results/rc_check.txt
experiments/tailcalls/cross.sh          # results/cross_targets.txt
```

Everything generated goes to `out/`, which is not committed.

## Files

- `cases/*.l0`: one program per shape. Each reads n from its first argument
  and makes a chain of n L0 calls. `self`, `mutual` (arities 3 and 2),
  `mutual_wide` (10 and 2: more than arm64's 8 argument registers),
  `mutual7` (7 and 2: fits arm64's registers, not x86-64's 6), `listloop`
  (the tail call passes a fresh list, so the old one is released before the
  call), `walk` (build a list, then walk it by `tail`), `matchloop` (tail call
  in a match arm, passing a data value), `nested` (an `if` inside the tail
  call's argument, whose join slot lands inside the loop body), `nontail`
  (baseline, not a tail call).
- `tailify.py`: the prototype rewrites. `--ret-direct` returns from each
  branch instead of joining through a slot; `--tail`, `--musttail`,
  `--musttail-same-arity`, `--tailcc`, `--pad-arity`, `--pad-component`,
  `--selfloop` [`--no-hoist`]; see its docstring.
- `proto/*.ll`: minimal hand-written IR showing the three musttail rules that
  matter: the join shape is rejected, differing arities under the C
  convention are rejected, differing arities under tailcc are accepted.
- The `noinl` builds add `noinline` to every function, a model of a program
  large enough that its recursive functions are not inlined into `main`. At
  -O2 the toy cases are otherwise inlined whole, which hides what happens to
  a real program's tail calls.
- `depth.sh`: finds the deepest n a binary survives (to within 1%).
- `callsites.sh`: lists calls between L0 functions in arm64 assembly as `bl`
  (grows the stack) or `b` (a jump).
- `results/`: the output of every script above, as recorded.
