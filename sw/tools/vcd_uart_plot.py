#!/usr/bin/env python3
"""Render a small set of UART-related signals from a VCD into a PNG.

This is a lightweight alternative to gtkwave screenshots (uses PIL).

Usage:
  vcd_uart_plot.py <in.vcd> <out.png> [t_end_ns]

Signals (hierarchical names) expected from soc_top_basic_tb dump:
- soc_top_basic_tb.uart_tx
- soc_top_basic_tb.dut.u_fab.u_uart.tx_state
- soc_top_basic_tb.dut.u_fab.u_uart.tx_count
- soc_top_basic_tb.dut.u_fab.u_uart.baud_cnt
- soc_top_basic_tb.dut.u_fab.u_uart.bauddiv

If some signals are missing, they will be skipped.
"""

from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def parse_vcd(vcd_text: str):
    id_to_name = {}
    timescale = (1, "ns")

    lines = iter(vcd_text.splitlines())
    in_def = True
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith("$timescale"):
            # read until $end
            buf = []
            while True:
                l2 = next(lines).strip()
                if l2.startswith("$end"):
                    break
                buf.append(l2)
            ts = " ".join(buf).strip()
            # e.g. "1ns" or "10 ps"
            ts = ts.replace(" ", "")
            num = ""; unit = ""
            for ch in ts:
                if ch.isdigit():
                    num += ch
                else:
                    unit += ch
            if num and unit:
                timescale = (int(num), unit)
            continue

        if line.startswith("$var"):
            # $var wire 1 ! clk $end
            parts = line.split()
            if len(parts) >= 5:
                width = int(parts[2])
                vid = parts[3]
                name = parts[4]
                # scope names are embedded via $scope/$upscope in real VCD,
                # but $dumpvars(0, top) produces fully qualified names for many simulators.
                id_to_name[vid] = (name, width)
            continue

        if line.startswith("$enddefinitions"):
            in_def = False
            break

    # Now parse value changes
    time = 0
    changes = {}  # name -> list[(time, value_str)]

    def record(vid: str, val: str):
        if vid not in id_to_name:
            return
        name, width = id_to_name[vid]
        changes.setdefault(name, []).append((time, val))

    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.startswith('#'):
            time = int(line[1:])
            continue
        if line[0] in '01xz':
            # scalar: 1!
            record(line[1:], line[0])
            continue
        if line[0] in 'bB':
            # vector: b1010 <id>
            parts = line.split()
            if len(parts) == 2:
                val = parts[0][1:]
                vid = parts[1]
                record(vid, val)
            continue

    return timescale, changes


def to_int(v: str) -> int | None:
    if v in ('x', 'z'):
        return None
    if all(c in '01' for c in v):
        return int(v, 2)
    if v in ('0', '1'):
        return int(v)
    return None


def step_segments(samples, t_end):
    # samples: list[(t,val)] sorted
    if not samples:
        return []
    out = []
    for i, (t, v) in enumerate(samples):
        t2 = samples[i+1][0] if i+1 < len(samples) else t_end
        out.append((t, t2, v))
    return out


def render(vcd_path: Path, out_path: Path, t_end: int):
    ts, changes = parse_vcd(vcd_path.read_text(errors='ignore'))

    # We rely on vvp/iverilog naming: use simple names if hierarchical missing.
    wanted = [
        ("uart_tx", "UART_TX"),
        ("tx_state", "TX_STATE"),
        ("tx_count", "TX_COUNT"),
        ("baud_cnt", "BAUD_CNT"),
        ("bauddiv", "BAUDDIV"),
    ]

    # find keys by suffix match
    selected = []
    for suffix, label in wanted:
        key = None
        for k in changes.keys():
            if k.endswith(suffix):
                key = k
                break
        if key is not None:
            selected.append((key, label))

    if not selected:
        raise SystemExit("No expected signals found in VCD")

    # Canvas
    W = 1400
    row_h = 90
    top = 40
    left = 160
    H = top + row_h * len(selected) + 20

    img = Image.new("RGB", (W, H), (18, 18, 18))
    dr = ImageDraw.Draw(img)
    font = ImageFont.load_default()

    # Title
    dr.text((10, 10), f"VCD: {vcd_path.name}  t_end={t_end} ticks", fill=(220,220,220), font=font)

    # Time axis
    def x_of(t):
        return int(left + (t / t_end) * (W - left - 20))

    # grid
    for frac in [0.0,0.25,0.5,0.75,1.0]:
        x = x_of(t_end*frac)
        dr.line((x, top-5, x, H-10), fill=(45,45,45))
        dr.text((x-10, top-25), f"{int(frac*100)}%", fill=(140,140,140), font=font)

    for idx, (key, label) in enumerate(selected):
        y0 = top + idx*row_h
        y_mid = y0 + 35
        dr.text((10, y0+5), label, fill=(200,200,200), font=font)
        dr.text((10, y0+20), key[-60:], fill=(120,120,120), font=font)
        # baseline
        dr.line((left, y_mid, W-20, y_mid), fill=(60,60,60))

        segs = step_segments(changes[key], t_end)
        # If vector, we draw as annotated changes.
        scalar = all(len(v)==1 and v in '01xz' for _, v in changes[key])

        if scalar:
            for t1, t2, v in segs:
                x1 = x_of(t1)
                x2 = x_of(t2)
                if v == '1':
                    yy = y_mid - 18
                    col = (0, 220, 120)
                elif v == '0':
                    yy = y_mid + 18
                    col = (0, 140, 255)
                else:
                    yy = y_mid
                    col = (220, 220, 0)
                dr.line((x1, yy, x2, yy), fill=col, width=2)
                # vertical edge at transition
                dr.line((x1, y_mid-18, x1, y_mid+18), fill=(90,90,90))
        else:
            # draw small markers and value text
            for t, v in changes[key]:
                if t > t_end:
                    break
                x = x_of(t)
                dr.line((x, y_mid-22, x, y_mid+22), fill=(90,90,90))
                vi = to_int(v)
                txt = str(vi) if vi is not None else v
                dr.text((x+2, y0+55), txt, fill=(220,220,220), font=font)

    img.save(out_path)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <in.vcd> <out.png> [t_end]", file=sys.stderr)
        raise SystemExit(2)
    vcd = Path(sys.argv[1])
    out = Path(sys.argv[2])
    t_end = int(sys.argv[3]) if len(sys.argv) >= 4 else 2000
    render(vcd, out, t_end)


if __name__ == '__main__':
    main()
