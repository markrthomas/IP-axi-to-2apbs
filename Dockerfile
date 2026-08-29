# syntax=docker/dockerfile:1
# -----------------------------------------------------------------------------
# IP-axi-to-2apbs — license-free UVM-on-Verilator image.
#
# Reproduces the `UVM on Verilator` CI gate (.github/workflows/verilator-sim.yml)
# in a container: builds the same SystemVerilog UVM env (uvm/sv + uvm/tb) under
# open-source Verilator and runs it scoreboard/UVM_ERROR-gated (make -C uvm/vlt
# ci).  Intended for a RAM-generous host (Railway) since the --binary build OOMs
# small local boxes.
#
#   Build:  docker build -t ip-axi-2apbs-uvm .
#   Run  :  docker run --rm ip-axi-2apbs-uvm                 # full UVM gate
#           docker run --rm ip-axi-2apbs-uvm make simple     # one top
#           docker run --rm ip-axi-2apbs-uvm verilator --version
#   Railway (batch / cron job, no listening port): see railway.toml.
#
# NOTE: unlike the sibling axi-on-ucie-to-mem image (which pins oss-cad-suite's
# Verilator), this flow REQUIRES a UVM-capable Verilator >= 5.050 built from
# source — the oss-cad-suite Verilator cannot elaborate/run UVM.
# -----------------------------------------------------------------------------

# ---- Stage 1: build UVM-capable Verilator from source -----------------------
FROM ubuntu:24.04 AS verilator-build

# Pinned to the v5.050 release tag (matches the workflow + local ~/verilator).
ARG VERILATOR_REF=v5.050
ARG VERILATOR_PREFIX=/opt/verilator
ENV DEBIAN_FRONTEND=noninteractive

# Same build dependencies as .github/workflows/verilator-sim.yml.
RUN apt-get update && apt-get install -y --no-install-recommends \
      git help2man perl python3 make autoconf g++ flex bison ccache \
      libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev \
      zlib1g zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${VERILATOR_REF}" \
      https://github.com/verilator/verilator /tmp/verilator-src
WORKDIR /tmp/verilator-src
RUN autoconf \
    && ./configure --prefix="${VERILATOR_PREFIX}" \
    && make -j"$(nproc)" \
    && make install

# `make install` does not install test_regress/; keep the bundled UVM library
# (uvm_pkg_all_v2020_3_1_dpi.svh + v2020_3_1/dpi/uvm_dpi.cc) beside the install
# so UVM_HOME is self-contained in the image.
RUN mkdir -p "${VERILATOR_PREFIX}/uvm" \
    && cp -a test_regress/t/uvm/. "${VERILATOR_PREFIX}/uvm/"

# ---- Stage 2: runtime image that builds + runs the UVM env ------------------
FROM ubuntu:24.04 AS uvm

ARG VERILATOR_PREFIX=/opt/verilator
ENV DEBIAN_FRONTEND=noninteractive

# Force a UTF-8 locale + Python I/O encoding. Cloud builders (Railway/CI) start
# the container under a C/POSIX locale, so any non-ASCII byte in the UVM/report
# output would raise UnicodeEncodeError on an ASCII sink and abort the run.
# ubuntu:24.04 ships C.UTF-8, so this needs no locale-gen; output is byte-
# identical on a UTF-8 sink and only stops the crash on an ASCII one.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=UTF-8 PYTHONUTF8=1

# Toolchain to compile the generated --binary C++ and run the sim:
#   g++/make          - build the generated model
#   perl              - the `verilator` launcher is a Perl script
#   ccache            - the generated build Makefile invokes `ccache g++`
#   z3                - SystemVerilog constraint solving at run time
#   libgoogle-perftools-dev, zlib - libs verilator_bin / the build may link
RUN apt-get update && apt-get install -y --no-install-recommends \
      g++ make perl python3 ccache z3 \
      libgoogle-perftools-dev zlib1g zlib1g-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=verilator-build /opt/verilator /opt/verilator

# Point the flow at the bundled toolchain.  VERILATOR_ROOT is deliberately left
# unset — the launcher derives it from its own path, and a stale value makes it
# hard-error (see uvm/vlt/README.md); the entrypoint also unsets it defensively.
ENV VERILATOR="${VERILATOR_PREFIX}/bin/verilator" \
    UVM_HOME="${VERILATOR_PREFIX}/uvm" \
    PATH="${VERILATOR_PREFIX}/bin:${PATH}"

# Bound the --binary C++ build parallelism.  Cloud builders advertise many cores
# but little RAM, so the UVM compile at high -j OOM-kills the compiler; 2 keeps
# peak memory bounded.  Raise it where RAM is ample, or lower to 1 on the
# smallest instances.  The entrypoint passes this to make as BUILD_JOBS.
ENV BUILD_JOBS=2

WORKDIR /work
COPY . /work

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Fail fast if the toolchain didn't assemble correctly.
RUN "${VERILATOR}" --version \
    && test -f "${UVM_HOME}/uvm_pkg_all_v2020_3_1_dpi.svh" \
    && test -f "${UVM_HOME}/v2020_3_1/dpi/uvm_dpi.cc" \
    && z3 --version

# Default: the full license-free UVM gate (make -C uvm/vlt ci) with the toolchain
# overrides injected by the entrypoint.  Override args to run a subset, e.g.
#   docker run --rm ip-axi-2apbs-uvm make simple
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
