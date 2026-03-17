# Minimal baremetal build for CowCat32 SoC

RISCV_PREFIX ?= riscv64-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump

CFLAGS  := -march=rv32i -mabi=ilp32 -mcmodel=medany -ffreestanding -fno-builtin \
          -nostdlib -nostartfiles -O2 -g -Wall -Wextra

LDSCRIPT := ../../common/link_soc.ld
START    := ../../common/start.S
COMMON_C := ../../common/uart.c ../../common/exit.c

OUTDIR := out
TARGET := uart_hello

ELF := $(OUTDIR)/$(TARGET).elf
TMP := $(OUTDIR)/$(TARGET).objcopy.vh
VH   := $(OUTDIR)/$(TARGET).vh
IMEMV:= $(OUTDIR)/imem.v
BIN  := $(OUTDIR)/$(TARGET).bin

all: $(VH) $(IMEMV)

$(OUTDIR):
	mkdir -p $(OUTDIR)

$(ELF): $(OUTDIR) main.c $(START) $(COMMON_C) $(LDSCRIPT)
	$(CC) $(CFLAGS) -T$(LDSCRIPT) $(START) main.c $(COMMON_C) -o $@

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(TMP): $(ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

$(VH): $(TMP)
	python3 ../../tools/objcopy_vh_to_wordvh.py $< $@
	@echo "Built $@"

$(IMEMV): $(VH)
	python3 ../../tools/wordvh_to_imem_v.py $(VH) $@
	@echo "Built $@"

dump: $(ELF)
	$(OBJDUMP) -d $< | less

clean:
	rm -rf $(OUTDIR)

.PHONY: all clean dump
