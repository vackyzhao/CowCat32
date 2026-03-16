#include "mmio.h"
#include "dma.h"

// STATUS bits
#define DMA_ST_BUSY (1u<<0)
#define DMA_ST_DONE (1u<<1)
#define DMA_ST_ERR  (1u<<2)

// CTRL bits (W1)
#define DMA_CTL_START    (1u<<0)
#define DMA_CTL_CLR_DONE (1u<<1)
#define DMA_CTL_CLR_ERR  (1u<<2)

void dma_config(const dma_desc_t *d) {
  MMIO32(DMA_SRC) = d->src;
  MMIO32(DMA_DST) = d->dst;
  MMIO32(DMA_LEN) = d->len;
}

void dma_start(void) {
  MMIO32(DMA_CTRL) = DMA_CTL_START;
}

uint32_t dma_status(void) {
  return MMIO32(DMA_STATUS);
}

int dma_busy(void) {
  return (dma_status() & DMA_ST_BUSY) != 0;
}

int dma_done(void) {
  return (dma_status() & DMA_ST_DONE) != 0;
}

int dma_err(void) {
  return (dma_status() & DMA_ST_ERR) != 0;
}

uint32_t dma_erraddr(void) {
  return MMIO32(DMA_ERRADDR);
}

void dma_clear_done(void) {
  MMIO32(DMA_CTRL) = DMA_CTL_CLR_DONE;
}

void dma_clear_err(void) {
  MMIO32(DMA_CTRL) = DMA_CTL_CLR_ERR;
}

int dma_wait(void) {
  while (!dma_done() && !dma_err()) {
    // spin
  }
  return dma_err() ? 0 : 1;
}

static int aligned4(uint32_t x) {
  return (x & 3u) == 0;
}

int dma_memcpy32(uint32_t dst, uint32_t src, uint32_t len) {
  if (!aligned4(dst) || !aligned4(src) || (len & 3u) || (len == 0)) {
    return 0;
  }

  dma_desc_t d = { .src = src, .dst = dst, .len = len };
  dma_clear_done();
  dma_clear_err();
  dma_config(&d);
  dma_start();
  return dma_wait();
}
