#include <stdint.h>
#include "../../common/mmio.h"
#include "../../common/uart.h"
#include "../../common/gpio.h"
#include "../../common/dma.h"
#include "../../common/timer.h"

static void tohost(uint32_t code) {
  MMIO32(TOHOST_ADDR) = code;
}

static void fail(uint32_t code, const char *msg) {
  uart_puts("FAIL: ");
  uart_puts(msg);
  uart_puts("\n");
  uart_flush();
  tohost(code);
  while (1) {}
}

int main(void) {
  // Fast sim bauddiv. FPGA(100MHz,115200): 868
  uart_init(8);
  uart_puts("soc all-test: gpio+timer+dma+uart\n");

  // GPIO
  gpio_set_dir(0xFFFFffffu);
  gpio_write(0x00000001u);
  if (gpio_read_out() != 0x00000001u) fail(10, "gpio readback");
  uart_puts("gpio ok\n");

  // TIMER: enable + mtime increments
  timer_clear();
  timer_enable(1);
  uint64_t t0 = timer_read_mtime();
  // wait until it advances by >= 20us
  while ((timer_read_mtime() - t0) < 20u) {}
  uint64_t t1 = timer_read_mtime();
  if (t1 <= t0) fail(20, "timer not increment");

  // TIMER: cmp/hit
  timer_set_cmp(t1 + 50u);
  timer_wait_hit();
  if (!timer_hit()) fail(21, "timer hit");
  uart_puts("timer ok\n");

  // DMA: copy 64 bytes in DMEM
  volatile uint32_t *src = (volatile uint32_t *)(uintptr_t)0x00002000u;
  volatile uint32_t *dst = (volatile uint32_t *)(uintptr_t)0x00003000u;
  for (int i = 0; i < 16; i++) src[i] = (uint32_t)(0xA5000000u + (uint32_t)i);
  for (int i = 0; i < 16; i++) dst[i] = 0;

  if (!dma_memcpy32(0x00003000u, 0x00002000u, 64u)) {
    fail(30, "dma start/wait");
  }

  for (int i = 0; i < 16; i++) {
    uint32_t exp = (uint32_t)(0xA5000000u + (uint32_t)i);
    if (dst[i] != exp) {
      fail(31, "dma compare");
    }
  }
  uart_puts("dma ok\n");

  uart_puts("PASS\n");
  uart_flush();
  tohost(1);
  while (1) {}
}
