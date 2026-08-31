TOPLEVEL_LANG = verilog
SIM ?= icarus

THIS_DIR        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VERILOG_SOURCES = $(abspath $(THIS_DIR)/../../src/axi3lite_regblock.v)
TOPLEVEL        = axi3lite_regblock
MODULE          = test_regblock

ICARUS_BIN_DIR ?= /usr/bin
export PYTHONPATH := $(THIS_DIR):$(PYTHONPATH)
SIM_CMD_PREFIX     := env -u VIRTUAL_ENV -u PYTHONHOME
export PYGPI_PYTHON_BIN := $(shell cocotb-config --python-bin)

include $(shell cocotb-config --makefiles)/Makefile.sim
