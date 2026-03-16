#pragma once
#include <stdint.h>

// Simple 32-bit DMA driver for CowCat32 MMIO DMA
// DMA_BASE = 0x1000_2000
// HW constraints:
//  - SRC/DST must be 4-byte aligned
//  - LEN must be multiple of 4

typedef struct {
  uint32_t src;
  uint32_t dst;
  uint32_t len; // bytes
} dma_desc_t;

void dma_config(const dma_desc_t *d);
void dma_start(void);

uint32_t dma_status(void);
int dma_busy(void);
int dma_done(void);
int dma_err(void);
uint32_t dma_erraddr(void);

void dma_clear_done(void);
void dma_clear_err(void);

// Busy-wait until DONE or ERR. Returns 1 on success, 0 on error.
int dma_wait(void);

// Convenience: memcpy-like DMA transfer (returns 1 on success, 0 on error).
int dma_memcpy32(uint32_t dst, uint32_t src, uint32_t len);
