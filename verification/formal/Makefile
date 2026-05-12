SBY ?= sby

.PHONY: all simple clean

all: simple

simple: bmc cover

bmc:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run BMC"; exit 0; }
	$(SBY) -f apb4_simple.sby bmc

cover:
	@command -v $(SBY) >/dev/null 2>&1 || { echo "[FORMAL] sby not found; install SymbiYosys to run cover"; exit 0; }
	$(SBY) -f apb4_simple.sby cover

clean:
	rm -rf apb4_simple_bmc/ apb4_simple_cover/

.PHONY: all simple bmc cover clean
