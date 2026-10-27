"""One analysis pass: collect → detect → report → notify."""
from __future__ import annotations

import logging
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional

from . import ai, detectors, local_checks, notify
from .collectors import collect_device_logs, collect_local_mac
from .config import SEVERITY_LEVELS
from .models import Alert, Event
from .report import build_report, sort_alerts
from .state import State

log = logging.getLogger(__name__)

DEFAULT_INTERVAL = 15 * 60
DATED_FILE = re.compile(r"(\d{4}-\d{2}-\d{2})")

# sender(subject, body, short_body) -> (delivered count, errors)
Sender = Callable[[str, str, str], tuple]


@dataclass
class Result:
    events: List[Event]
    alerts: List[Alert]
    notified: List[Alert]
    report: str
    report_path: Path
    errors: List[str]


def _prune_files(data_dir: Path, cutoff: float) -> None:
    cutoff_day = time.strftime("%Y-%m-%d", time.localtime(cutoff))
    for path in list((data_dir / "logs").glob("*/*.log")) + list((data_dir / "reports").glob("*.txt")):
        m = DATED_FILE.search(path.name)
        if m and m.group(1) < cutoff_day:
            path.unlink()


def run_once(cfg, now: Optional[float] = None, send: bool = True, sender: Optional[Sender] = None) -> Result:
    now = now or time.time()
    gen, det, local = cfg["general"], cfg["detect"], cfg["local_mac"]
    data_dir = Path(gen["data_dir"]).expanduser()
    (data_dir / "logs").mkdir(parents=True, exist_ok=True)
    (data_dir / "reports").mkdir(parents=True, exist_ok=True)

    state = State(str(data_dir / "state.db"))
    try:
        first_run = state.get_float("first_run")
        if first_run is None:
            first_run = now
            state.set_kv("first_run", now)
        last_run = state.get_float("last_run") or now - DEFAULT_INTERVAL
        minutes = max((now - last_run) / 60, 1.0)
        learning = now - first_run < gen["learning_days"] * 86400

        events = collect_device_logs(data_dir / "logs", state)
        events += collect_local_mac(local, state, now)
        for ev in events:
            state.touch_device(ev.device, ev.ts)

        device_names = [d["name"] for d in cfg["devices"]]
        alerts = detectors.apply_rules(events, detectors.compile_rules(cfg))
        alerts += detectors.detect_new_login_ips(events, state, cfg, learning, now)
        alerts += detectors.detect_new_macs(events, state, cfg, learning, now)
        alerts += detectors.detect_unknown_senders(events, state, now)
        alerts += detectors.detect_volume(events, state, cfg, device_names, now, minutes)
        alerts += detectors.detect_silence(state, cfg, now, first_run)
        if local["enabled"] and sys.platform == "darwin":
            if local["check_panics"]:
                alerts += local_checks.check_panics(state, local["name"], now)
            if local["check_launch_items"]:
                alerts += local_checks.check_launch_items(state, local["name"], now)
        alerts += local_checks.check_disk(str(data_dir), local["name"], local["disk_usage_percent"])

        cooldown = det["alert_cooldown_minutes"] * 60
        for a in alerts:
            last = state.alert_last_sent(a.key)
            a.suppressed = last is not None and now - last < cooldown
        alerts = sort_alerts(alerts)

        min_level = SEVERITY_LEVELS[gen["min_notify_severity"]]
        to_notify = [a for a in alerts if not a.suppressed and SEVERITY_LEVELS[a.severity] >= min_level]

        summary = ""
        if to_notify and cfg["ai"]["enabled"]:
            summary = ai.summarise(cfg["ai"], to_notify, events)

        report = build_report(alerts, events, last_run, now, learning, summary)
        report_path = data_dir / "reports" / time.strftime("%Y-%m-%d_%H%M.txt", time.localtime(now))
        report_path.write_text(report, encoding="utf-8")

        # `delivered` decides whether notify-level alerts start their cooldown.
        delivered, errors = False, []
        if send and to_notify:
            top = to_notify[0]
            subject = f"[Home Guard] {len(to_notify)} 則警報:{top.title} ({top.device})"
            short = build_report(to_notify, events, last_run, now, learning, summary, compact=True)
            if sender is None and not notify.enabled_channels(cfg):
                log.warning("有警報但沒有啟用任何通知管道")
                delivered = True  # nothing to retry
            else:
                count, errors = (sender or (lambda s, b, sb: notify.send_all(cfg, s, b, sb)))(subject, report, short)
                delivered = count > 0

        notified = set(id(a) for a in to_notify)
        for a in alerts:
            if a.suppressed:
                continue
            # Undelivered notifications stay eligible so the next run retries them.
            if id(a) not in notified or delivered:
                state.mark_alert_sent(a.key, now)
            state.log_alert(now, a)

        state.set_kv("last_run", now)
        cutoff = now - gen["retention_days"] * 86400
        state.prune(cutoff)
        _prune_files(data_dir, cutoff)
        state.commit()
    finally:
        state.close()
    return Result(events, alerts, to_notify if send and delivered else [], report, report_path, errors)
