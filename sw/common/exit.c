#include "mmio.h"
#include "uart.h"
#include "exit.h"

__attribute__((noreturn)) void _exit(int code) {
  // best-effort flush uart first (if enabled)
  uart_flush();

  // SoC TB expects tohost at 0x1000.
  MMIO32(TOHOST_ADDR) = (uint32_t)code;

  // Helpful during interactive debugging (may be ignored by core).
  __asm__ volatile ("ebreak");

  while (1) {
    // park
  }
}
