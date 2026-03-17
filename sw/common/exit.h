#pragma once
#include <stdint.h>

// Terminate program execution.
// Default behavior: park forever (infinite loop).
// If you want simulation to stop, write TOHOST yourself before returning.
__attribute__((noreturn)) void _exit(int code);
