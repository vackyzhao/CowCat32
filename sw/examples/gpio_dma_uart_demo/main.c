#include <stdint.h>
#include "../../common/mmio.h"
#include "../../common/uart.h"
#include "../../common/gpio.h"
#include "../../common/dma.h"

static void tohost(uint32_t code) {
  MMIO32(TOHOST_ADDR) = code;
}

int main(void) {
  uart_init(8);
  uart_puts("gpio/dma/uart demo\n");

  // GPIO
  gpio_set_dir(0xFFFFffffu);
  gpio_write(0x00000001u);
  uart_puts("gpio ok\n");

  // DMA: copy 64 bytes in DMEM
  volatile uint32_t *src = (volatile uint32_t *)(uintptr_t)0x00002000u;
  volatile uint32_t *dst = (volatile uint32_t *)(uintptr_t)0x00003000u;
  for (int i = 0; i < 16; i++) src[i] = (uint32_t)i;
  for (int i = 0; i < 16; i++) dst[i] = 0;

  if (!dma_memcpy32(0x00003000u, 0x00002000u, 64u)) {
    uart_puts("dma err\n");
    tohost(2);
    while (1) {}
  }

  for (int i = 0; i < 16; i++) {
    if (dst[i] != (uint32_t)i) {
      uart_puts("dma cmp fail\n");
      tohost(3);
      while (1) {}
    }
  }
  uart_puts("dma ok\n");

  uart_flush();
  tohost(1);
  while (1) {}
}
