#!/usr/bin/env python3
"""
plot_waves.py - Ish Bedi

Draws the waveform figures in docs/ straight from the simulation VCD files,
in a GTKWave-style dark theme. Run `make waves` (it re-runs the sims first).
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
DOCS = os.path.join(ROOT, "docs")

BG, GRID, FG = "#0b0f14", "#26313d", "#d8dee9"
GREEN, YELLOW, ORANGE, PURPLE, CYAN, RED = "#3ddc84", "#e5c07b", "#ff9f43", "#b48ead", "#56b6c2", "#ef5350"


# ---------------------------------------------------------------- VCD reader
def read_vcd(path, wanted, t_end_ps):
    """Return {signal_name: [(time_ps, value_str), ...]} for the wanted names.
    Names are full hierarchical paths, e.g. 'tb_uart.u_tx.state'."""
    ids, scope, out = {}, [], {w: [] for w in wanted}
    t = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("$scope"):
                scope.append(line.split()[2])
            elif line.startswith("$upscope"):
                scope.pop()
            elif line.startswith("$var"):
                p = line.split()
                name = ".".join(scope + [p[4]])
                if name in out:
                    ids.setdefault(p[3], []).append(name)
            elif line.startswith("$enddefinitions"):
                break
        for line in f:
            if not line or line[0] == "$":
                continue
            c = line[0]
            if c == "#":
                t = int(line[1:])
                if t > t_end_ps:
                    break
            elif c in "01xzXZ":
                for n in ids.get(line[1:].strip(), ()):
                    out[n].append((t, c))
            elif c in "bB":
                v, i = line[1:].split()
                for n in ids.get(i, ()):
                    out[n].append((t, v))
    missing = [w for w in wanted if not out[w]]
    if missing:
        sys.exit(f"signals not found in {path}: {missing}")
    return out


def val_at(series, t):
    v = series[0][1]
    for ts, x in series:
        if ts > t:
            break
        v = x
    return v


def as_int(v):
    try:
        return int(v, 2)
    except ValueError:
        return None


# ---------------------------------------------------------------- drawing
def setup(n_rows, title, t0, t1, width=13):
    fig, ax = plt.subplots(figsize=(width, 0.62 * n_rows + 1.2), dpi=150)
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    ax.set_xlim(t0, t1)
    ax.set_ylim(-0.6, n_rows - 0.2)
    ax.tick_params(colors=FG, labelsize=8)
    for s in ax.spines.values():
        s.set_color(GRID)
    ax.set_yticks([])
    ax.grid(axis="x", color=GRID, linewidth=0.6)
    ax.set_xlabel("time (µs)", color=FG, fontsize=9)
    ax.set_title(title, color=FG, fontsize=11, loc="left", pad=10)
    return fig, ax


def row_label(ax, row, n_rows, text, t0):
    y = n_rows - 1 - row
    ax.annotate(text, xy=(0, y + 0.25), xycoords=("axes fraction", "data"), xytext=(-6, 0),
                textcoords="offset points", ha="right", va="center", color=FG, fontsize=9,
                family="monospace", annotation_clip=False)
    return y


def draw_bit(ax, y, series, t0, t1, color, us):
    xs, ys = [], []
    prev = val_at(series, t0)
    xs.append(t0); ys.append(prev)
    for t, v in series:
        if t0 < t < t1:
            xs += [t, t]; ys += [prev, v]; prev = v
    xs.append(t1); ys.append(prev)
    yy = [y + (0.5 if v == "1" else 0.0) for v in ys]
    ax.plot([x / us for x in xs], yy, color=color, linewidth=1.3, drawstyle="default")
    hi = [(xs[i], xs[i + 1]) for i in range(len(xs) - 1) if ys[i] == "1" and xs[i + 1] > xs[i]]
    for a, b in hi:
        ax.fill_between([a / us, b / us], y, y + 0.5, color=color, alpha=0.18, linewidth=0)


def draw_bus(ax, y, series, t0, t1, color, us, fmt):
    pts = [(t0, val_at(series, t0))] + [(t, v) for t, v in series if t0 < t < t1]
    pts.append((t1, None))
    for (a, va), (b, _) in zip(pts, pts[1:]):
        if b <= a:
            continue
        xa, xb = a / us, b / us
        d = min((xb - xa) * 0.15, (t1 - t0) / us * 0.004)
        ax.fill([xa, xa + d, xb - d, xb, xb - d, xa + d], [y + .25, y + .5, y + .5, y + .25, y, y],
                facecolor=BG, edgecolor=color, linewidth=1.0)
        label = fmt(va)
        if label is not None and (xb - xa) > (t1 - t0) / us * 0.03:
            ax.text((xa + xb) / 2, y + 0.25, label, ha="center", va="center",
                    color=color, fontsize=7.5, family="monospace")


def hexfmt(width):
    def f(v):
        n = as_int(v)
        return "x" if n is None else f"{n:0{(width + 3) // 4}X}"
    return f


def statefmt(names):
    def f(v):
        n = as_int(v)
        return "x" if n is None else names.get(n, str(n))
    return f


def first_rise(series, after=0):
    prev = None
    for t, v in series:
        if t > after and v == "1" and prev != "1":
            return t
        prev = v
    raise RuntimeError("no rising edge")


def first_fall(series, after=0):
    prev = None
    for t, v in series:
        if t > after and v == "0" and prev == "1":
            return t
        prev = v
    raise RuntimeError("no falling edge")


# ---------------------------------------------------------------- figure 1
def fig_uart_frame():
    tb = "tb_uart"
    sig = {
        "start": f"{tb}.tx_start",
        "txst": f"{tb}.u_tx.state",
        "tick": f"{tb}.u_tx.bit_tick",
        "tx": f"{tb}.tx_line",
        "rxst": f"{tb}.u_rx.state",
        "shreg": f"{tb}.u_rx.shreg",
        "valid": f"{tb}.rx_valid",
        "data": f"{tb}.rx_data",
        "done": f"{tb}.tx_done",
    }
    d = read_vcd(os.path.join(BUILD, "tb_uart.vcd"), list(sig.values()), 400_000_000)
    s = {k: d[v] for k, v in sig.items()}
    t_fall = first_fall(s["tx"])
    bit = 434 * 20_000                                   # ps
    t0, t1 = t_fall - 0.8 * bit, t_fall + 11.2 * bit
    us = 1e6
    rows = [
        ("tx_start", "bit", "start", ORANGE),
        ("u_tx.state", "bus", "txst", CYAN),
        ("u_tx.bit_tick", "bit", "tick", ORANGE),
        ("tx (line)", "bit", "tx", GREEN),
        ("u_rx.state", "bus", "rxst", CYAN),
        ("u_rx.shreg[7:0]", "bus", "shreg", YELLOW),
        ("rx_valid", "bit", "valid", PURPLE),
        ("rx_data[7:0]", "bus", "data", YELLOW),
    ]
    st_names = {0: "IDLE", 1: "START", 2: "DATA", 3: "STOP"}
    fig, ax = setup(len(rows) + 1, "UART frame 0xA5 (8N1, 115200 baud, 50 MHz): TX -> RX loopback", t0 / us, t1 / us)
    n = len(rows) + 1
    for r, (label, kind, key, col) in enumerate(rows):
        y = row_label(ax, r + 1, n, label, t0)
        if kind == "bit":
            draw_bit(ax, y, s[key], t0, t1, col, us)
        else:
            fmt = statefmt(st_names) if key in ("txst", "rxst") else hexfmt(8)
            draw_bus(ax, y, s[key], t0, t1, col, us, fmt)

    # bit labels and boundaries along the top
    ytop = n - 1
    names = ["START"] + [f"D{i}" for i in range(8)] + ["STOP"]
    val = 0xA5
    for i, nm in enumerate(names):
        a, b = (t_fall + i * bit) / us, (t_fall + (i + 1) * bit) / us
        ax.axvline(a, color=GRID, linewidth=0.8, linestyle="--")
        lv = "0" if i == 0 else ("1" if i == 9 else str((val >> (i - 1)) & 1))
        ax.text((a + b) / 2, ytop + 0.25, f"{nm}\n{lv}", ha="center", va="center", color=FG, fontsize=7.5)
    ax.axvline((t_fall + 10 * bit) / us, color=GRID, linewidth=0.8, linestyle="--")
    # one bit-period dimension
    ya = n - 1 - 4 + 0.75
    a, b = (t_fall + bit) / us, (t_fall + 2 * bit) / us
    ax.annotate("", xy=(a, ya), xytext=(b, ya), arrowprops=dict(arrowstyle="<->", color=RED, lw=1))
    ax.text((a + b) / 2, ya + 0.12, "1 bit = 434 clk = 8.68 µs", color=RED, fontsize=7.5, ha="center")

    os.makedirs(DOCS, exist_ok=True)
    out = os.path.join(DOCS, "uart_frame.png")
    fig.tight_layout()
    fig.savefig(out, facecolor=BG)
    plt.close(fig)
    print("wrote", out)


# ---------------------------------------------------------------- figure 2
def fig_rx_sampling():
    tb = "tb_uart"
    sig = {"tx": f"{tb}.tx_line", "sync": f"{tb}.u_rx.rx_sync", "rxst": f"{tb}.u_rx.state",
           "os": f"{tb}.u_rx.os_cnt", "shreg": f"{tb}.u_rx.shreg"}
    d = read_vcd(os.path.join(BUILD, "tb_uart.vcd"), list(sig.values()), 400_000_000)
    s = {k: d[v] for k, v in sig.items()}
    t_fall = first_fall(s["tx"])
    bit = 434 * 20_000
    t0, t1 = t_fall - 0.3 * bit, t_fall + 3.2 * bit
    us = 1e6
    rows = [("tx (line)", "bit", "tx", GREEN), ("u_rx.rx_sync", "bit", "sync", GREEN),
            ("u_rx.state", "bus", "rxst", CYAN), ("u_rx.os_cnt", "bus", "os", ORANGE),
            ("u_rx.shreg[7:0]", "bus", "shreg", YELLOW)]
    n = len(rows)
    fig, ax = setup(n, "RX 16x oversampling: start bit re-checked at tick 8, data bits sampled at their centre (red dotted)",
                    t0 / us, t1 / us)
    st_names = {0: "IDLE", 1: "START", 2: "DATA", 3: "STOP"}
    for r, (label, kind, key, col) in enumerate(rows):
        y = row_label(ax, r, n, label, t0)
        if kind == "bit":
            draw_bit(ax, y, s[key], t0, t1, col, us)
        else:
            fmt = statefmt(st_names) if key == "rxst" else (lambda v: str(as_int(v)) if as_int(v) is not None else "x") if key == "os" else hexfmt(8)
            draw_bus(ax, y, s[key], t0, t1, col, us, fmt)
    # sample instants = where shreg changes, plus the start-bit check (state START->DATA)
    marks = [t for t, _ in s["shreg"] if t_fall < t < t1]
    prev = None
    for t, v in s["rxst"]:
        iv = as_int(v)
        if t0 < t < t1 and prev == 1 and iv == 2:
            marks.append(t)
        prev = iv
    for t in marks:
        ax.axvline(t / us, color=RED, linewidth=1, linestyle=":")
    for i in range(4):
        ax.axvline((t_fall + i * bit) / us, color=GRID, linewidth=0.8, linestyle="--")
    out = os.path.join(DOCS, "rx_sampling.png")
    fig.tight_layout()
    fig.savefig(out, facecolor=BG)
    plt.close(fig)
    print("wrote", out)


# ---------------------------------------------------------------- figure 3
def fig_command():
    tb = "tb_uart_alu"
    sig = {"host": f"{tb}.host_tx", "rxv": f"{tb}.dut.rx_valid", "rxd": f"{tb}.dut.rx_data",
           "st": f"{tb}.dut.state", "op": f"{tb}.dut.op_r", "a": f"{tb}.dut.a_r", "b": f"{tb}.dut.b_r",
           "res": f"{tb}.last_result", "flg": f"{tb}.last_flags", "fpga": f"{tb}.fpga_tx"}
    d = read_vcd(os.path.join(BUILD, "tb_uart_alu.vcd"), list(sig.values()), 2_000_000_000)
    s = {k: d[v] for k, v in sig.items()}
    bit = 434 * 20_000
    t_first = first_fall(s["host"])
    t0, t1 = t_first - 1.5 * bit, t_first + 52 * bit
    us = 1e6
    rows = [("host_tx  (PC -> FPGA)", "bit", "host", GREEN), ("rx_valid", "bit", "rxv", PURPLE),
            ("rx_data[7:0]", "bus", "rxd", YELLOW), ("state", "bus", "st", CYAN),
            ("op_r", "bus", "op", YELLOW), ("a_r", "bus", "a", YELLOW), ("b_r", "bus", "b", YELLOW),
            ("last_result", "bus", "res", YELLOW), ("last_flags VNCZ", "bus", "flg", YELLOW),
            ("fpga_tx  (FPGA -> PC)", "bit", "fpga", GREEN)]
    n = len(rows)
    fig, ax = setup(n, "Command ADD 0x7F, 0x01 over UART -> reply 0x80, flags V=1 N=1 C=0 Z=0",
                    t0 / us, t1 / us, width=14)
    st = {0: "GET_OP", 1: "GET_A", 2: "GET_B", 3: "EXEC", 4: "SEND_RES", 5: "SEND_FLG"}
    for r, (label, kind, key, col) in enumerate(rows):
        y = row_label(ax, r, n, label, t0)
        if kind == "bit":
            draw_bit(ax, y, s[key], t0, t1, col, us)
        else:
            if key == "st":
                fmt = statefmt(st)
            elif key == "flg":
                fmt = lambda v: (format(as_int(v), "04b") if as_int(v) is not None else "x")
            elif key == "op":
                fmt = lambda v: {0: "ADD", 1: "SUB", 2: "AND", 3: "OR", 4: "XOR", 5: "SHL", 6: "SHR", 7: "NOT"}.get(as_int(v), "x")
            else:
                fmt = hexfmt(8)
            draw_bus(ax, y, s[key], t0, t1, col, us, fmt)
    for i, lab in enumerate(["OP = 00", "A = 7F", "B = 01"]):
        x = (t_first + (i * 10 + 5) * bit) / us
        ax.text(x, n - 0.35, lab, color=GREEN, fontsize=8, ha="center")
    t_reply = first_fall(s["fpga"], after=t_first)
    for i, lab in enumerate(["RESULT = 80", "FLAGS = 0C"]):
        x = (t_reply + (i * 10 + 5) * bit) / us
        ax.text(x, 0.65, lab, color=GREEN, fontsize=8, ha="center")
    out = os.path.join(DOCS, "uart_alu_command.png")
    fig.tight_layout()
    fig.savefig(out, facecolor=BG)
    plt.close(fig)
    print("wrote", out)


if __name__ == "__main__":
    fig_uart_frame()
    fig_rx_sampling()
    fig_command()
