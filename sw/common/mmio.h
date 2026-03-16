#pragma once
#include <stdint.h>

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

// Keep tohost at 0x0000_1000 (SoC TB monitors this address)
#define TOHOST_ADDR  0x00001000u

// MMIO window
#define GPIO_BASE    0x10000000u
#define TIMER_BASE   0x10001000u
#define DMA_BASE     0x10002000u
#define UART_BASE    0x10003000u

// GPIO regs
#define GPIO_DATA    (GPIO_BASE + 0x00u)
#define GPIO_DIR     (GPIO_BASE + 0x04u)
#define GPIO_IN      (GPIO_BASE + 0x08u)

// TIMER regs
#define TIMER_CTRL   (TIMER_BASE + 0x00u)
#define TIMER_MTIME_LO (TIMER_BASE + 0x04u)
#define TIMER_MTIME_HI (TIMER_BASE + 0x08u)
#define TIMER_CMP_LO (TIMER_BASE + 0x0Cu)
#define TIMER_CMP_HI (TIMER_BASE + 0x10u)
#define TIMER_STATUS (TIMER_BASE + 0x14u)

// DMA regs
#define DMA_SRC      (DMA_BASE + 0x00u)
#define DMA_DST      (DMA_BASE + 0x04u)
#define DMA_LEN      (DMA_BASE + 0x08u)
#define DMA_CTRL     (DMA_BASE + 0x0Cu)
#define DMA_STATUS   (DMA_BASE + 0x10u)
#define DMA_ERRADDR  (DMA_BASE + 0x14u)

// UART regs
#define UART_TXDATA  (UART_BASE + 0x00u)
#define UART_RXDATA  (UART_BASE + 0x04u)
#define UART_STATUS  (UART_BASE + 0x08u)
#define UART_BAUDDIV (UART_BASE + 0x0Cu)
#define UART_CTRL    (UART_BASE + 0x10u)
