SBY ?= sby

.PHONY: all simple burst clean

all: simple burst

simple: simple-bmc simple-cover

burst: burst-bmc burst-cover

simple-bmc:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run BMC"; exit 0; }
	$(SBY) -f apb4_simple.sby bmc

simple-cover:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run cover"; exit 0; }
	$(SBY) -f apb4_simple.sby cover

burst-bmc:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run BMC"; exit 0; }
	$(SBY) -f apb4_burst.sby bmc

burst-cover:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run cover"; exit 0; }
	$(SBY) -f apb4_burst.sby cover

clean:
	rm -rf apb4_simple_bmc/ apb4_simple_cover/ apb4_burst_bmc/ apb4_burst_cover/

.PHONY: all simple burst simple-bmc simple-cover burst-bmc burst-cover clean
