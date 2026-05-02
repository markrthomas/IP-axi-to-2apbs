IVERILOG ?= iverilog
VVP ?= vvp
IVERILOG_FLAGS ?= -g2012 -Wall

SIMPLE_TB = test/tb_axi4_to_apb4_2x_simple.v
SIMPLE_RTL = src/axi4_to_apb4_2x_simple.v
BURST_TB = test/tb_axi4_to_apb4_2x_burst.v
BURST_EXT_TB = test/tb_axi4_to_apb4_2x_burst_extended.v
BURST_RTL = src/axi4_to_apb4_2x_burst.v
SIMPLE_WS_TB = test/tb_axi4_to_apb4_2x_simple_ws.v
WAIT_CYCLES ?= 2

.PHONY: test-simple test-simple-ws test-simple-ws-sweep test-burst test-burst-ext test-all lint clean

test-simple: sim_simple
	$(VVP) sim_simple

test-simple-ws: sim_simple_ws_$(WAIT_CYCLES)
	$(VVP) sim_simple_ws_$(WAIT_CYCLES)

test-simple-ws-sweep:
	$(MAKE) test-simple-ws WAIT_CYCLES=1
	$(MAKE) test-simple-ws WAIT_CYCLES=2
	$(MAKE) test-simple-ws WAIT_CYCLES=3

test-burst: sim_burst
	$(VVP) sim_burst

test-burst-ext: sim_burst_ext
	$(VVP) sim_burst_ext

test-all: test-simple test-burst test-burst-ext

lint:
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_simple_w $(SIMPLE_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -DREAD_WAIT_CYCLES=$(WAIT_CYCLES) -o /tmp/sim_simple_ws_w $(SIMPLE_WS_TB) $(SIMPLE_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_w $(BURST_TB) $(BURST_RTL)
	$(IVERILOG) $(IVERILOG_FLAGS) -o /tmp/sim_burst_ext_w $(BURST_EXT_TB) $(BURST_RTL)

sim_simple: $(SIMPLE_TB) $(SIMPLE_RTL)
	$(IVERILOG) -g2012 -o $@ $^

sim_burst: $(BURST_TB) $(BURST_RTL)
	$(IVERILOG) -g2012 -o $@ $^

sim_burst_ext: $(BURST_EXT_TB) $(BURST_RTL)
	$(IVERILOG) -g2012 -o $@ $^

sim_simple_ws_%: $(SIMPLE_WS_TB) $(SIMPLE_RTL)
	$(IVERILOG) -g2012 -DREAD_WAIT_CYCLES=$* -o $@ $^

clean:
	rm -f sim_simple sim_burst sim_burst_ext sim_simple_ws_*
