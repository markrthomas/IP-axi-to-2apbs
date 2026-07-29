.PHONY: all simple burst pyuvm_burst clean

all: simple burst pyuvm_burst

simple:
	$(MAKE) -C simple

burst:
	$(MAKE) -C burst

pyuvm_burst:
	$(MAKE) -C pyuvm_burst

clean:
	$(MAKE) -C simple clean
	$(MAKE) -C burst clean
	$(MAKE) -C pyuvm_burst clean
	$(MAKE) -C pyuvm_waves clean
