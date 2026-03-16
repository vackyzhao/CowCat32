#include "mmio.h"
#include "timer.h"

void timer_enable(int en) {
  uint32_t ctrl = MMIO32(TIMER_CTRL);
  ctrl = (ctrl & ~1u) | (en ? 1u : 0u);
  MMIO32(TIMER_CTRL) = ctrl;
}

void timer_clear(void) {
  // CTRL bit1 clear
  MMIO32(TIMER_CTRL) = (MMIO32(TIMER_CTRL) | (1u<<1));
}

uint64_t timer_read_mtime(void) {
  // Hardware latch: read HI latches snapshot, then LO returns snapshot LO
  uint32_t hi = MMIO32(TIMER_MTIME_HI);
  uint32_t lo = MMIO32(TIMER_MTIME_LO);
  return ((uint64_t)hi << 32) | (uint64_t)lo;
}

void timer_set_cmp(uint64_t cmp) {
  MMIO32(TIMER_CMP_LO) = (uint32_t)(cmp & 0xFFFFFFFFu);
  MMIO32(TIMER_CMP_HI) = (uint32_t)(cmp >> 32);
}

int timer_hit(void) {
  return (MMIO32(TIMER_STATUS) & 1u) != 0;
}

void timer_wait_hit(void) {
  while (!timer_hit()) {
    // spin
  }
}
