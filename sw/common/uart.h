#pragma once
#include <stdint.h>

void uart_init(uint32_t bauddiv);
void uart_putc(char c);
void uart_puts(const char *s);

// Non-blocking helpers
int  uart_tx_full(void);
int  uart_rx_valid(void);
int  uart_getc_nonblock(char *out);
