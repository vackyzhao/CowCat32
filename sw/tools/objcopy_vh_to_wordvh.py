import re
import sys
from pathlib import Path

hex8 = re.compile(r"^[0-9A-Fa-f]{8}$")


def bswap32(s: str) -> str:
    v = int(s, 16)
    b0 = (v >> 0) & 0xFF
    b1 = (v >> 8) & 0xFF
    b2 = (v >> 16) & 0xFF
    b3 = (v >> 24) & 0xFF
    w = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    return f"{w:08x}"


def main(tmp_path: str, out_path: str):
    src = Path(tmp_path)
    dst = Path(out_path)

    out = []
    for line in src.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('@'):
            a = int(line[1:], 16)  # byte addr
            out.append(f"@{a >> 2:08x}")
            continue
        toks = line.split()
        out.append(' '.join(bswap32(t) if hex8.match(t) else t for t in toks))

    dst.write_text('\n'.join(out) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <objcopy_tmp.vh> <out.vh>", file=sys.stderr)
        raise SystemExit(2)
    main(sys.argv[1], sys.argv[2])
