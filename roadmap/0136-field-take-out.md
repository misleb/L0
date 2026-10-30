# 0136: a field taken out, updated, and put back, in place

Kind: language
Status: proposed
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
