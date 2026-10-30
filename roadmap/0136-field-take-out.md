# 0136: a field taken out, updated, and put back, in place

Kind: language
Status: done
Needs: 0132

## Why

A field holding an array or a map, updated and put back, copies when
written with fields: in `(.ctx p (call_result (.ctx p) v))` the read holds
the context while `p` does too, so `call_result`'s `array_set` copies its
104 words, where `(match p ((Proc s c m w st) (Proc s (call_result c v) m w
-1)))` releases `p` once it has the fields and updates in place. So 0132's
step 2 left `match` in the kernel's `resume`, `kset`, `kresume`,
`kmapped`, `run`, and `give`, and in the examples' `space_put`, each with
a comment saying why (changelog, "Named fields", *Found in step 2*).
Section 6.5's third form already does this for an element of an array:
`(array_set g y (f ... (array_get g y) ...))` takes the element out for
`f` and puts the result back. The smallest program that cannot be written
in place: a process's context updated through its field.

```
(def resume ((p Proc) (v int)) Proc
  (.state (.ctx p (call_result (.ctx p) v)) -1))
```

## The form

`(.f r (g a1 ... (.f r) ... an))`, where `r` is one variable that no other
argument of `g` mentions and `f` is a field of `r`'s type: when `r` has no
other holder, the field is taken out of `r` for `g`, leaving 0 in its
place as `l0_array_take` does, and `g`'s result is put back; otherwise the
field is read as written. Evaluation order, the errors' order, and the
results are those of the plain reading, as 6.5 promises for the row form.
One runtime function, `l0_data_take(b, i)`, beside `l0_array_take`, and
the emitter's `row_update_of` and `through_args` extended to `EWith`.

## Done when

- the checklist in the l0-bootstrap skill
- spec 5.8 and 6.5 state the form, and 10.3 the runtime function
- `tests/io/fields_in_place` gains the mode: a loop updating an array
  inside a record reports 0 copies
- after the seed is refreshed: the kernel's six functions and the
  examples' `space_put` are written with fields, and `--virt` is green
  with `L0_ARRAY_STATS` showing no copies from them
- `roadmap/l0s-adoption.md` section 2 no longer tells L0S to leave arrays
  and maps inside records to `match`, and shows the form instead

## Log

- 2026-10-30: opened, from 0132's step 2; proposed.
- 2026-10-30: active; step 1 done. Spec 5.8, 6.5, and 10.3 say the form;
  `l0_data_take` in `l0rt.ll`; `field_through` in emit.l0 rewrites the
  argument to a `data.take` pseudo-call, as `through_args` does for rows.
  `tests/io/fields_in_place` has a `through` mode: 100,000 steps, 0
  copies, where the seed copied once per step. The first run found that
  both forms took the element or field even when the variable was used
  after the update, which 6.5 counts as another holder; the array form
  had done so since 0076. Both now take only at the variable's last use,
  and `array_test` and `fields_test` hold the cases. Both suites, the
  fixpoint, and `--virt` on both boards green; seed refreshed;
  self-compile 0.69 s. Next: step 2, the kernel and `space_put`.
- 2026-10-30: step 2 done. The kernel's `resume` is the field form, and
  `kset`, `kresume`, `kmapped`, `run`, and `give` replace `.procs` through
  `update_at`, which takes the per-process step as a function (0135), or
  `mapped_at`; the examples' `space_put` is the field form. The board has
  no environment for `L0_ARRAY_STATS`, so the measure is a host program
  with the kernel's `Proc`, `Kern`, `update_at`, `kset`, `kresume`, and
  `give`: 10,000 rounds, 0 copies, 140,004 sets in place, under
  `L0_RC_CHECK`. Both suites and `--virt` on both boards green; the
  adoption guide's section 2 shows the form. Done.
