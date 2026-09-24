# The image tools/linux-test.sh runs the test suites in. Built locally and
# never pushed. clang is pinned to one major version so a run does not change
# with what Ubuntu ships; it is also older than a current Homebrew LLVM, so
# the two together cover the range of LLVM the seed must parse.
FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq clang-18 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/clang-18 /usr/local/bin/clang

# Not root, so that a file without read permission really cannot be read,
# which tests/io/filecopy.sh checks.
RUN useradd -m tester
USER tester
WORKDIR /home/tester
