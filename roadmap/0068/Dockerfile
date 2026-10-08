# Prototype for roadmap item 0068: an image that only links bare-metal ELF
# images, since the host's ld.lld is blocked. Not tools/linux's test image.
# docker build --platform linux/arm64 -t l0-link-proto:arm64 roadmap/0068
FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends lld-18 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/ld.lld-18 /usr/local/bin/ld.lld
