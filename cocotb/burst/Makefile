TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(PWD)/../../src/axi4_to_apb4_2x_burst.v
TOPLEVEL        = axi4_to_apb4_2x_burst
MODULE          = test_burst_bridge

ICARUS_BIN_DIR ?= /usr/bin
export PYTHONPATH := $(PWD)/..:$(PYTHONPATH)
SIM_CMD_PREFIX     := env -u VIRTUAL_ENV -u PYTHONHOME
export PYGPI_PYTHON_BIN := $(shell cocotb-config --python-bin)

include $(shell cocotb-config --makefiles)/Makefile.sim
