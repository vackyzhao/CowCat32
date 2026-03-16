#include <stdint.h>
#include "../../common/mmio.h"
#include "../../common/uart.h"

static void tohost(uint32_t code) {
  MMIO32(TOHOST_ADDR) = code;
}

int main(void) {
  // For simulation you can set this smaller (e.g. 8). For FPGA at 100MHz+115200: 868.
  uart_init(8);

  uart_puts("Hello from C via UART!\n");

  // wait for TX fifo empty and shifter idle
  uart_flush();

  // quick GPIO pattern (optional)
  MMIO32(GPIO_DIR) = 0xFFFFffffu;
  MMIO32(GPIO_DATA) = 0xA5A55A5Au;

  tohost(1);
  while (1) {}
}
