# 0144: the library's names made consistent, with aliases for the old

Kind: tooling
Status: done
Needs: nothing

## Why

The spec calls them regions; the library calls them devices
(`open_device`, `IoDevice`, `device_read32`). Constructor pairs differ in
shape: `IoOpened`/`IoFailed` against `DeviceOpened`/`DeviceFailed`,
`IoBytes`/`IoReadFailed` against `IoLine`/`IoError`. Function names put the
noun first in `file_write_str` and last in `rename_file`, and
`open_appending` is a gerund beside `open_in`. `lib/io.l0`'s own header
states a rule its newer types break.

L0S uses the device wrappers in 41 files: 298 `IoDevice`, 200
`device_write32`, 188 `device_read32`, 55 `DeviceOpened`, 43
`open_device`. A rename alone would break all of them.

## The change

- one rule, written in `lib/io.l0`'s header, and every public name made
  to follow it; the spec's words win where the library differs (region,
  not device)
- every old name kept as a documented alias, a `def` calling the new one
  or a type kept beside the new, marked in its `;;` as the old name; an
  alias costs nothing at link time, since an unused function is deleted
  (README, "The standard library"), and nothing at the call, since the
  call inlines
- `roadmap/l0s-adoption.md` gains the table of old and new names, and the
  aliases go once L0S has moved

## Done when

- `tools/l0 doc` shows the new names with the old beside them, and
  `tests/io/libdoc/index.txt` is regenerated and its diff read
- every test and example uses the new names; a test keeps each alias
- the changelog records the rule and the renames
- `roadmap/l0s-adoption.md` has the table of old and new names, a grep for
  the old ones, and the date the aliases go

## Log

- 2026-10-30: opened, from the review (its item 2.4); proposed.
- 2026-10-30: done. The rule is in `lib/io.l0`'s header; the region
  family is renamed, `IoRegion`, `IoRegionOpened`, `RegionFault`,
  `open_region`, `close_region`, `region_get8` to `region_set_bytes`,
  with every old name an alias documented as "The old name of ...".
  Left as they were, and why, in the changelog: `open_appending` (the
  builtin has `open_append`), `IoLine`'s `IoError`, and `Trap`. The
  examples, `tests/virt`'s device tests, and `lib/AGENTS.md` use the new
  names; `tests/unit/device_test` keeps the aliases tested.
  `tests/io/libdoc/index.txt` regenerated and read. Both suites and
  `--virt` on both boards green. The adoption guide's section 10 has the
  table, the grep, and when the aliases go.
