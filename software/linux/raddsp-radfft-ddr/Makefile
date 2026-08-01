obj-m += raddsp_radfft_ddr.o

KDIR ?= /lib/modules/$(shell uname -r)/build
CC ?= $(CROSS_COMPILE)gcc

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

examples: examples/radfft_ddr_ctl

examples/radfft_ddr_ctl: examples/radfft_ddr_ctl.c raddsp_radfft_ddr.h
	$(CC) -Wall -Wextra -O2 -I$(CURDIR) -o $@ $<

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	$(RM) examples/radfft_ddr_ctl
