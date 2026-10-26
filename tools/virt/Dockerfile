# The image tools/l0 links QEMU virt board images in, for --target virt,
# when L0_VIRT_LD names no ld.lld and none is on PATH. Built locally the first
# time it is needed and never pushed. It holds only the linker: clang on the
# host compiles and optimizes the whole program into one object, so the
# container's older LLVM never reads the host's bitcode.
FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends lld-18 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/ld.lld-18 /usr/local/bin/ld.lld
