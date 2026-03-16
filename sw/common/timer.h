#pragma once
#include <stdint.h>

// Timer driver for CowCat32 TIMER (mtime 1MHz)

void timer_enable(int en);
void timer_clear(void);

// Atomic read (hardware latch): read HI then LO
uint64_t timer_read_mtime(void);

void timer_set_cmp(uint64_t cmp);
int  timer_hit(void);

// Busy-wait until hit becomes 1
void timer_wait_hit(void);
