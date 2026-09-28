#!/usr/bin/env python3
"""quietOS benchmark harness: bench / compare.

Subcommands:
  bench    build -Dperf, boot under QEMU, parse [PERF], persist the serial log
  compare  compare base vs head serial logs, render the PR markdown table

Environment independent: only counters (vga.stores, vga.flushes) are asserted,
never cycles (KVM vs TCG differ by 10-50x).

Exit codes:
  0  pass (no regression)
  1  regression detected
  2  infrastructure error (crash, hang, no [PERF], missing log)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time

PERF_RE = re.compile(r"^\[PERF\] (\S+)((?: \S+=\d+)+)$")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COUNTER_KEYS = ("vga.stores", "vga.flushes")
QEMU_TIMEOUT_S = 300


def parse_serial(text):
    """'[PERF] terminal.char cycles=... vga.stores=960000 vga.flushes=500' -> dict."""
    metrics = {}
    for line in text.splitlines():
        if line.startswith("[PERF] done"):
            continue
        m = PERF_RE.match(line)
        if m:
            name, pairs = m.group(1), m.group(2).split()
            metrics[name] = {k: int(v) for k, v in (p.split("=") for p in pairs)}
    return metrics


def run_qemu(iso, use_kvm):
    fd, log_path = tempfile.mkstemp(prefix="quiet-perf-", suffix=".log")
    os.close(fd)
    cmd = ["qemu-system-i386", "-cdrom", iso, "-serial", f"file:{log_path}",
           "-monitor", "stdio", "-display", "none", "-no-reboot",
           "-no-shutdown", "-m", "64"]
    if use_kvm and os.path.exists("/dev/kvm"):
        cmd.append("-enable-kvm")
    qemu = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    deadline = time.time() + QEMU_TIMEOUT_S
    done = False
    try:
        while time.time() < deadline:
            if qemu.poll() is not None:
                break
            try:
                with open(log_path, "rb") as f:
                    if b"[PERF] done" in f.read():
                        done = True
                        break
            except FileNotFoundError:
                pass
            time.sleep(0.25)
        try:
            qemu.stdin.write(b"quit\n")
            qemu.stdin.flush()
        except (BrokenPipeError, OSError):
            pass
        qemu.wait(timeout=10)
        with open(log_path, "r", errors="replace") as f:
            text = f.read()
    finally:
        os.unlink(log_path)
    return text, done


def build_iso(optimize):
    subprocess.run(["zig", "build", "iso-grub", f"-Doptimize={optimize}", "-Dperf"],
                   cwd=REPO_ROOT, check=True)


def run_bench(optimize, use_kvm):
    build_iso(optimize)
    text, done = run_qemu(os.path.join(REPO_ROOT, "quiet-grub.iso"), use_kvm)
    if not done:
        print("error: kernel crashed or hung before [PERF] done", file=sys.stderr)
        sys.exit(2)
    metrics = parse_serial(text)
    if not metrics:
        print("error: no [PERF] lines in serial log (built with -Dperf?)", file=sys.stderr)
        sys.exit(2)
    return text, metrics


def parse_log_file(path):
    with open(path) as f:
        return parse_serial(f.read())


def compare_metrics(base, head):
    """One verdict per workload: ✨ new (head only), 🗑 removed (base only),
    🔴/🟢/✅ on shared workloads."""
    verdicts = []
    for name in sorted(set(base) | set(head)):
        b, h = base.get(name), head.get(name)
        if b is None:
            verdicts.append({"name": name, "base": None, "head": h, "status": "✨"})
        elif h is None:
            verdicts.append({"name": name, "base": b, "head": None, "status": "🗑"})
        else:
            deltas = {k: h.get(k, 0) - b.get(k, 0) for k in COUNTER_KEYS}
            status = ("🔴" if any(deltas[k] > 0 for k in deltas)
                      else "🟢" if any(deltas[k] < 0 for k in deltas)
                      else "✅")
            verdicts.append({"name": name, "base": b, "head": h,
                             "deltas": deltas, "status": status})
    return verdicts


def render_markdown(verdicts, base_label, head_label, optimize, kvm):
    rows = []
    for v in verdicts:
        name = v["name"]
        if v["status"] == "✨":
            s = v["head"].get("vga.stores", "—")
            fl = v["head"].get("vga.flushes", "—")
            rows.append(f"| {name} | — → {s} | — | — → {fl} | — | ✨ nouveau |")
        elif v["status"] == "🗑":
            s = v["base"].get("vga.stores", "—")
            fl = v["base"].get("vga.flushes", "—")
            rows.append(f"| {name} | {s} → — | — | {fl} → — | — | 🗑 supprimé |")
        else:
            d = v["deltas"]
            rows.append(
                f"| {name} | {v['base'].get('vga.stores', '—')} → {v['head'].get('vga.stores', '—')} "
                f"| {d['vga.stores']:+d} | {v['base'].get('vga.flushes', '—')} → {v['head'].get('vga.flushes', '—')} "
                f"| {d['vga.flushes']:+d} | {v['status']} |"
            )
    regressions = sum(1 for v in verdicts if v["status"] == "🔴")
    improvements = sum(1 for v in verdicts if v["status"] == "🟢")
    new = sum(1 for v in verdicts if v["status"] == "✨")
    removed = sum(1 for v in verdicts if v["status"] == "🗑")
    return "\n".join([
        f"## Benchmark counters (`{optimize} -Dperf`, {'KVM' if kvm else 'TCG'})",
        f"**base `{base_label}` vs head `{head_label}`**",
        "",
        "| Workload | stores (base → head) | Δ stores | flushes (base → head) | Δ flushes | Verdict |",
        "|---|---|---|---|---|---|",
        *rows,
        "",
        f"**Result: {regressions} regression(s), {improvements} improvement(s), "
        f"{new} new, {removed} removed | "
        f"{'REGRESSION ❌' if regressions else 'PASS ✅'}**",
        "",
    ])


def cmd_bench(args):
    text, metrics = run_bench(args.optimize, args.kvm)
    with open(args.log, "w") as f:
        f.write(text)
    if args.out:
        with open(args.out, "w") as f:
            json.dump(metrics, f, indent=2)
    print(f"bench done -> {args.log}")


def cmd_compare(args):
    for path in (args.base_log, args.head_log):
        if not os.path.exists(path):
            print(f"error: missing log: {path}", file=sys.stderr)
            sys.exit(2)
    base = parse_log_file(args.base_log)
    head = parse_log_file(args.head_log)
    verdicts = compare_metrics(base, head)
    table = render_markdown(verdicts, args.base_label, args.head_label,
                            args.optimize, args.kvm)
    print(table)
    if args.out:
        with open(args.out, "w") as f:
            f.write(table)
    regressions = sum(1 for v in verdicts if v["status"] == "🔴")
    sys.exit(1 if regressions else 0)


def main():
    ap = argparse.ArgumentParser(prog="perf.py",
                                 description="quietOS benchmark harness (bench / compare)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_bench = sub.add_parser("bench")
    p_bench.add_argument("--optimize", default="ReleaseFast")
    p_bench.add_argument("--kvm", action="store_true", help="use -enable-kvm if /dev/kvm exists")
    p_bench.add_argument("--log", required=True, help="serial log output path (persisted)")
    p_bench.add_argument("--out", help="optional metrics JSON output path")
    p_bench.set_defaults(func=cmd_bench)

    p_cmp = sub.add_parser("compare")
    p_cmp.add_argument("base_log", help="serial log from the base checkout")
    p_cmp.add_argument("head_log", help="serial log from the head checkout")
    p_cmp.add_argument("--base-label", default="base")
    p_cmp.add_argument("--head-label", default="head")
    p_cmp.add_argument("--optimize", default="ReleaseFast", help="display only (header)")
    p_cmp.add_argument("--kvm", action="store_true", help="display only: header shows KVM instead of TCG")
    p_cmp.add_argument("--out", help="write markdown table to this path")
    p_cmp.set_defaults(func=cmd_compare)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
