#include "mmio.h"
#include "uart.h"

// STATUS bits (see README)
#define UART_ST_TX_BUSY   (1u<<0)
#define UART_ST_TX_FULL   (1u<<1)
#define UART_ST_TX_EMPTY  (1u<<2)
#define UART_ST_RX_VALID  (1u<<3)
#define UART_ST_RX_FULL   (1u<<4)
#define UART_ST_OVERRUN   (1u<<5)

// CTRL bits
#define UART_CTL_TX_EN     (1u<<0)
#define UART_CTL_RX_EN     (1u<<1)
#define UART_CTL_LOOPBACK  (1u<<2)
#define UART_CTL_CLR_OVR   (1u<<3)

int uart_tx_full(void) {
  return (MMIO32(UART_STATUS) & UART_ST_TX_FULL) != 0;
}

int uart_tx_empty(void) {
  return (MMIO32(UART_STATUS) & UART_ST_TX_EMPTY) != 0;
}

int uart_tx_busy(void) {
  return (MMIO32(UART_STATUS) & UART_ST_TX_BUSY) != 0;
}

int uart_rx_valid(void) {
  return (MMIO32(UART_STATUS) & UART_ST_RX_VALID) != 0;
}

void uart_init(uint32_t bauddiv) {
  MMIO32(UART_BAUDDIV) = bauddiv;
  MMIO32(UART_CTRL) = (UART_CTL_TX_EN | UART_CTL_RX_EN);
}

void uart_putc(char c) {
  while (uart_tx_full()) {
    // spin
  }
  MMIO32(UART_TXDATA) = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s) {
  while (*s) {
    if (*s == '\n') uart_putc('\r');
    uart_putc(*s++);
  }
}

int uart_getc_nonblock(char *out) {
  if (!uart_rx_valid()) return 0;
  uint32_t v = MMIO32(UART_RXDATA);
  *out = (char)(v & 0xFFu);
  return 1;
}

char uart_getc_blocking(void) {
  char c;
  while (!uart_getc_nonblock(&c)) {
    // spin
  }
  return c;
}

void uart_flush(void) {
  while (!uart_tx_empty()) {
    // wait fifo empty
  }
  while (uart_tx_busy()) {
    // wait shifter idle
  }
}
