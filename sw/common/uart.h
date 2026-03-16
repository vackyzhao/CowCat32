#pragma once
#include <stdint.h>

void uart_init(uint32_t bauddiv);
void uart_putc(char c);
void uart_puts(const char *s);

// status helpers
int  uart_tx_full(void);
int  uart_tx_empty(void);
int  uart_tx_busy(void);
int  uart_rx_valid(void);

// RX helpers
int  uart_getc_nonblock(char *out);
char uart_getc_blocking(void);

// Wait until all queued characters are transmitted
void uart_flush(void);
