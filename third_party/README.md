# third_party

This folder is for **local** third-party dependencies used during simulation (e.g. riscv-tests).

It is intentionally **not tracked** by git to keep the repository small.

## Expected contents

- `riscv-tests/` (https://github.com/riscv-software-src/riscv-tests)

The regression scripts expect:

```
third_party/riscv-tests/isa/rv32ui
```

## How to fetch

```bash
mkdir -p third_party
cd third_party

git clone --depth=1 https://github.com/riscv-software-src/riscv-tests
```

If you have an existing copy, just place it at `third_party/riscv-tests`.
