TOPLEVEL_LANG = verilog
SIM ?= icarus

VERILOG_SOURCES = $(CURDIR)/../../src/axi3lite_regblock.v
TOPLEVEL        = axi3lite_regblock
MODULE          = test_regblock

ICARUS_BIN_DIR ?= /usr/bin
export PYTHONPATH := $(CURDIR):$(PYTHONPATH)
SIM_CMD_PREFIX     := env -u VIRTUAL_ENV -u PYTHONHOME
export PYGPI_PYTHON_BIN := $(shell cocotb-config --python-bin)

include $(shell cocotb-config --makefiles)/Makefile.sim
