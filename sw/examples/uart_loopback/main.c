#include <stdint.h>
#include "../../common/mmio.h"
#include "../../common/uart.h"

#define UART_CTL_TX_EN     (1u << 0)
#define UART_CTL_RX_EN     (1u << 1)
#define UART_CTL_LOOPBACK  (1u << 2)

static void tohost(uint32_t code) {
  MMIO32(TOHOST_ADDR) = code;
}

int main(void) {
  char c0, c1;

  // Fast simulation baud, with internal loopback enabled.
  MMIO32(UART_BAUDDIV) = 8;
  MMIO32(UART_CTRL) = UART_CTL_TX_EN | UART_CTL_RX_EN | UART_CTL_LOOPBACK;

  uart_putc('O');
  uart_putc('K');
  uart_flush();

  c0 = uart_getc_blocking();
  c1 = uart_getc_blocking();

  if (c0 != 'O') tohost(2);
  if (c1 != 'K') tohost(3);

  tohost(1);
  return 0;
}
