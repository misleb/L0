# 0108: a Pi 5 boot loop, one command from source to serial log

Kind: tooling
Status: done; run on the board 2026-10-24
Needs: nothing

## Why

0098's first run on a Pi 5 (see its Log, 2026-10-24) took these steps by
hand, and every later check on the board (0110) repeats them:

- `L0_VIRT_LD=/usr/bin/ld.lld tools/l0 build --target pi5 PROG -o IMG`,
  since there is no Docker here
- `tools/l0 card IMG tmp/tftp`
- fetch `bcm2712-rpi-5-b.dtb` from raspberrypi/firmware into `tmp/tftp`
- `sudo dnsmasq -d --port=0 --enable-tftp --tftp-root=... --listen-address=...
  --bind-interfaces --user=... --log-dhcp --log-facility=-`, which needs
  root for port 69 and so cannot be started by the agent
- capture `/dev/ttyUSB0` at 115200 into a file while the board is
  power-cycled

The Pi's router hands out DHCP option 66 naming this machine, so no DHCP
server is run. The board's firmware asks for `SERIAL/config.txt` first, then
the root, and probes for `armstub8-2712.bin`, overlays, and `pieeprom.sig`,
all of which may be not found.

## Done when

- `tools/pi5-run PROG [ARG ...] < input` builds the image, writes the
  TFTP root under `tmp/`, fetches the device tree once and keeps it,
  captures the serial port to a log under `tmp/`, and prints the log's
  program part, from the BL31 line to the firmware's `Halt:` line
- it finds the linker and the TFTP server's address itself, and says what
  it needs when it finds none; it never writes outside `tmp/`
- the TFTP server stays a step the user starts with `sudo`, printed as a
  command, unless a way without root is found (a capability on the server's
  binary is the user's call, not the script's)
- it is described in `tools/l0`'s header or the `l0-bootstrap` skill's
  tool list, not in `roadmap/`

## Log

- 2026-10-24: opened after 0098's first run. Next: write the script, run
  it against `tests/virt/pi5/uart.l0` on the board.
- 2026-10-24: `tools/pi5-run` written and first run with `uart.l0`. That
  run proved nothing, and this item was marked done wrongly: the server
  already running served `tmp/tftp`, not the `tmp/pi5/tftp` the script
  staged, so the Pi booted the old image and printed its output. It showed
  when a probe's run printed `hi from the pi`. The script checks only that
  something listens on port 69.
- 2026-10-24: fixed. The script reads the running dnsmasq's `--tftp-root`
  from `ps`, stages there if it is under `tmp/`, and stops if it is not or
  cannot be read. Run on the board with 0109's probe and then the revised
  `uart.l0`, and each printed its own output, so the staged image is the one
  booted. The server's start stays a `sudo` step the script prints; no
  capability or sysctl was set. Listed in the l0-bootstrap skill. Not
  covered: a run with standard input or boot arguments (0110's checks will be
  the first), `--no-build`, and a server that is not dnsmasq.
