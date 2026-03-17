#pragma once
#include <stdint.h>

// Terminate program execution.
// In simulation TB, writing to TOHOST triggers $finish/$fatal.
// On FPGA, this will just park the CPU.
__attribute__((noreturn)) void _exit(int code);
