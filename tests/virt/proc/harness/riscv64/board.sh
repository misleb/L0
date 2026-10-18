# Where kernel.ll beside this file reads what boot.sh loads for it, on
# QEMU's riscv64 virt board with -m 1G, and how QEMU boots it, through
# OpenSBI, whose banner on QEMU's standard output keeps the serial line on
# a descriptor of its own: sourced by boot.sh.
H_INPUT_LEN_AT=0x8FFFFFF8
H_INPUT_AT=0x90000000
H_ARGS_LEN_AT=0x9EFFFFF8
H_ARGS_AT=0x9F000000
H_SLOT_BASE=0x98000000
H_QEMU=qemu-system-riscv64
H_QEMU_ARGS="-M virt,aia=none -m 1G -semihosting -global virtio-mmio.force-legacy=false"
H_SERIAL=fd3
