#pragma once
#include <stdint.h>

// Simple GPIO driver for CowCat32 MMIO GPIO
// GPIO_BASE = 0x1000_0000

void gpio_set_dir(uint32_t dir);
uint32_t gpio_get_dir(void);

void gpio_write(uint32_t value);
uint32_t gpio_read_out(void);
uint32_t gpio_read_in(void);

void gpio_set_bits(uint32_t mask);
void gpio_clear_bits(uint32_t mask);
void gpio_toggle_bits(uint32_t mask);

// Read-modify-write helper
void gpio_write_masked(uint32_t mask, uint32_t value);
