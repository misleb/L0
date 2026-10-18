# Where kernel.ll beside this file reads what boot.sh loads for it, on
# QEMU's aarch64 virt board with -m 2G, and how QEMU boots it: sourced by
# boot.sh.
H_INPUT_LEN_AT=0x4FFFFFF8
H_INPUT_AT=0x50000000
H_ARGS_LEN_AT=0x5EFFFFF8
H_ARGS_AT=0x5F000000
H_SLOT_BASE=0x58000000
H_QEMU=qemu-system-aarch64
H_QEMU_ARGS="-M virt -cpu cortex-a72 -m 2G -semihosting -global virtio-mmio.force-legacy=false"
H_SERIAL=stdio
