"""Checks on the Mac mini itself that don't come from log lines."""
from __future__ import annotations

import glob
import os
import plistlib
import shutil
from typing import Iterable, List

from .models import Alert
from .state import State

PANIC_DIRS = ("/Library/Logs/DiagnosticReports",)
LAUNCH_DIRS = ("/Library/LaunchDaemons", "/Library/LaunchAgents", "/Users/*/Library/LaunchAgents")


def _scan_new(state: State, kind: str, paths: Iterable[str], now: float) -> List[str]:
    """Return paths not seen before. The first scan only records a baseline."""
    first_scan = state.get_kv(f"{kind}_scan_done") is None
    new = [p for p in sorted(paths) if state.add_known(kind, "local", p, now)]
    state.set_kv(f"{kind}_scan_done", 1)
    return [] if first_scan else new


def check_panics(state: State, device: str, now: float, dirs=PANIC_DIRS) -> List[Alert]:
    paths = [p for d in dirs for p in glob.glob(os.path.join(d, "*.panic"))]
    return [
        Alert("kernel_panic", "critical", "macOS 發生 kernel panic", device, os.path.basename(p), 1, [], p)
        for p in _scan_new(state, "panic", paths, now)
    ]


def _launch_program(path: str) -> str:
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
    except Exception:
        return ""
    prog = data.get("Program") or (data.get("ProgramArguments") or [""])[0]
    return str(prog)


def check_launch_items(state: State, device: str, now: float, dirs=LAUNCH_DIRS) -> List[Alert]:
    paths = [p for d in dirs for p in glob.glob(os.path.join(d, "*.plist"))]
    alerts = []
    for p in _scan_new(state, "launch_item", paths, now):
        prog = _launch_program(p)
        alerts.append(Alert(
            "new_launch_item", "warning", "新增開機自動執行項目 (LaunchAgent/Daemon)", device,
            os.path.basename(p), 1, [], p + (f" → {prog}" if prog else ""),
        ))
    return alerts


def check_disk(path: str, device: str, threshold_pct: float) -> List[Alert]:
    if not threshold_pct:
        return []
    usage = shutil.disk_usage(path)
    pct = usage.used / usage.total * 100
    if pct < threshold_pct:
        return []
    return [Alert(
        "disk_space", "warning", "Mac mini 磁碟空間不足", device, "", 1, [],
        f"{path} 已使用 {pct:.0f}% (剩 {usage.free / 1e9:.1f} GB)",
    )]
