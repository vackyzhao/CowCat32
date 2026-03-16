#include "mmio.h"
#include "gpio.h"

void gpio_set_dir(uint32_t dir) {
  MMIO32(GPIO_DIR) = dir;
}

uint32_t gpio_get_dir(void) {
  return MMIO32(GPIO_DIR);
}

void gpio_write(uint32_t value) {
  MMIO32(GPIO_DATA) = value;
}

uint32_t gpio_read_out(void) {
  return MMIO32(GPIO_DATA);
}

uint32_t gpio_read_in(void) {
  return MMIO32(GPIO_IN);
}

void gpio_set_bits(uint32_t mask) {
  MMIO32(GPIO_DATA) = gpio_read_out() | mask;
}

void gpio_clear_bits(uint32_t mask) {
  MMIO32(GPIO_DATA) = gpio_read_out() & ~mask;
}

void gpio_toggle_bits(uint32_t mask) {
  MMIO32(GPIO_DATA) = gpio_read_out() ^ mask;
}

void gpio_write_masked(uint32_t mask, uint32_t value) {
  uint32_t cur = gpio_read_out();
  cur = (cur & ~mask) | (value & mask);
  MMIO32(GPIO_DATA) = cur;
}
