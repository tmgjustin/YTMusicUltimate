"""Human-readable reports."""
from __future__ import annotations

import time
from collections import Counter
from typing import List

from .config import SEVERITY_LEVELS
from .models import Alert, Event

ICONS = {"critical": "🔴 嚴重", "warning": "🟠 警告", "info": "🔵 資訊"}


def _fmt(ts: float) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))


def sort_alerts(alerts: List[Alert]) -> List[Alert]:
    return sorted(alerts, key=lambda a: (-SEVERITY_LEVELS[a.severity], -a.count, a.device))


def build_report(alerts: List[Alert], events: List[Event], start: float, end: float,
                 learning: bool, ai_summary: str = "", compact: bool = False) -> str:
    active = [a for a in alerts if not a.suppressed]
    suppressed = len(alerts) - len(active)
    counts = Counter(ev.device for ev in events)
    lines = [
        f"🛡 Home Guard {_fmt(end)}",
        f"期間 {_fmt(start)} – {time.strftime('%H:%M', time.localtime(end))} | "
        f"事件 {len(events)} 筆 | 裝置 {len(counts)} 台",
    ]
    if learning:
        lines.append("(學習期中:新 IP / 新裝置只記錄、不發警報)")
    if ai_summary:
        lines += ["", "🤖 AI 摘要", ai_summary]

    for severity in ("critical", "warning", "info"):
        group = [a for a in sort_alerts(active) if a.severity == severity]
        if not group or (compact and severity == "info"):
            continue
        lines += ["", f"{ICONS[severity]} ({len(group)})"]
        for a in group:
            count = f" ×{a.count}" if a.count > 1 else ""
            detail = f" — {a.detail}" if a.detail else ""
            lines.append(f"• [{a.device}] {a.title}{count}{detail}")
            for sample in a.samples[: 1 if compact else 3]:
                lines.append(f"    {sample[:160] if compact else sample}")

    if not active:
        lines += ["", "✅ 沒有發現異常"]
    if suppressed:
        lines.append(f"(另有 {suppressed} 則重複警報在冷卻時間內,未重複列出)")
    if counts and not compact:
        lines += ["", "各裝置事件數: " + ", ".join(f"{d} {c}" for d, c in counts.most_common())]
    return "\n".join(lines) + "\n"
