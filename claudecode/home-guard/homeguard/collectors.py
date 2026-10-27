"""Collect new events: stored syslog files and the Mac mini's unified log."""
from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from .models import Event
from .parser import parse_syslog
from .state import State

log = logging.getLogger(__name__)

# `log show` messageType -> syslog-like severity
MESSAGE_TYPE_SEVERITY = {"Fault": 2, "Error": 3, "Default": 5, "Info": 6, "Debug": 7}


def parse_stored_line(line: str, device: str) -> Optional[Event]:
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) != 3:
        return None
    try:
        ts = datetime.fromisoformat(parts[0]).timestamp()
    except ValueError:
        return None
    _, severity, program, message = parse_syslog(parts[2])
    return Event(ts, device, message, program, severity, parts[1])


def collect_device_logs(logs_dir: Path, state: State) -> List[Event]:
    """Read lines appended to `<logs_dir>/<device>/*.log` since the last run."""
    events: List[Event] = []
    for path in sorted(Path(logs_dir).glob("*/*.log")):
        st = path.stat()
        inode, offset = state.get_offset(str(path))
        if inode != st.st_ino or offset > st.st_size:
            offset = 0
        if offset == st.st_size:
            continue
        with open(path, "rb") as f:
            f.seek(offset)
            data = f.read()
        end = data.rfind(b"\n")
        if end < 0:  # only a partial line so far
            continue
        device = path.parent.name
        for line in data[: end + 1].decode("utf-8", "replace").splitlines():
            ev = parse_stored_line(line, device)
            if ev:
                events.append(ev)
        state.set_offset(str(path), st.st_ino, offset + end + 1)
    return events


def _parse_log_ts(value: str) -> Optional[float]:
    for fmt in ("%Y-%m-%d %H:%M:%S.%f%z", "%Y-%m-%d %H:%M:%S%z"):
        try:
            return datetime.strptime(value, fmt).timestamp()
        except (TypeError, ValueError):
            continue
    return None


def parse_log_show_ndjson(text: str, device: str) -> List[Event]:
    events: List[Event] = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        msg = obj.get("eventMessage")
        ts = _parse_log_ts(obj.get("timestamp", ""))
        if not msg or ts is None:
            continue
        program = os.path.basename(obj.get("processImagePath") or "")
        events.append(Event(ts, device, msg, program, MESSAGE_TYPE_SEVERITY.get(obj.get("messageType"))))
    return events


def collect_local_mac(local_cfg, state: State, now: float, runner=subprocess.run) -> List[Event]:
    """Query the macOS unified log for the window since the previous run."""
    if not local_cfg["enabled"] or sys.platform != "darwin":
        return []
    start = now - local_cfg["max_lookback_minutes"] * 60
    last = state.get_float("mac_last_ts")
    if last:
        start = max(start, last)

    def fmt(t: float) -> str:
        return datetime.fromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")

    cmd = [
        "/usr/bin/log", "show", "--style", "ndjson", "--info",
        "--start", fmt(start), "--end", fmt(now),
        "--predicate", local_cfg["predicate"],
    ]
    try:
        proc = runner(cmd, capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.warning("log show failed: %s", exc)
        return []
    if proc.returncode != 0:
        log.warning("log show exited %s: %s", proc.returncode, proc.stderr.strip()[:500])
        return []
    state.set_kv("mac_last_ts", now)
    return parse_log_show_ndjson(proc.stdout, local_cfg["name"])
