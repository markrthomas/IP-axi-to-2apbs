TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(CURDIR)/../../src/axi4_to_apb4_2x_simple.v
TOPLEVEL        = axi4_to_apb4_2x_simple
MODULE          = test_simple_bridge

ICARUS_BIN_DIR ?= /usr/bin
export PYTHONPATH := $(CURDIR)/..:$(PYTHONPATH)
SIM_CMD_PREFIX     := env -u VIRTUAL_ENV -u PYTHONHOME
export PYGPI_PYTHON_BIN := $(shell cocotb-config --python-bin)

include $(shell cocotb-config --makefiles)/Makefile.sim
