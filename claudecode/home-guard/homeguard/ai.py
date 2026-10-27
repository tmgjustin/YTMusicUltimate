"""Optional: ask Claude Code (`claude -p`) to summarise the alerts in plain language."""
from __future__ import annotations

import logging
import subprocess
from typing import List

from .models import Alert, Event

log = logging.getLogger(__name__)

PROMPT = """你是家用網路與 macOS 的資安分析師。以下是 Home Guard 本次分析發現的警報與相關 log 樣本。
請用繁體中文、10 行以內回答:
1. 哪些警報最需要注意、可能原因(真的攻擊 / 設備故障 / 誤報)
2. 建議立即採取的具體動作
不要重複貼出原始 log。

## 警報
{alerts}

## 相關 log 樣本
{samples}
"""


def summarise(ai_cfg, alerts: List[Alert], events: List[Event]) -> str:
    alert_lines = "\n".join(
        f"- [{a.severity}] {a.title} | 裝置={a.device} {a.detail} | 次數={a.count}" for a in alerts
    )
    samples: List[str] = []
    for a in alerts:
        samples.extend(f"{a.device}: {s}" for s in a.samples)
    samples = samples[: ai_cfg["max_sample_lines"]]
    prompt = PROMPT.format(alerts=alert_lines, samples="\n".join(samples) or "(無)")
    try:
        proc = subprocess.run(
            list(ai_cfg["command"]) + [prompt],
            capture_output=True, text=True, timeout=ai_cfg["timeout_seconds"],
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.warning("AI summary failed: %s", exc)
        return ""
    if proc.returncode != 0:
        log.warning("AI summary exited %s: %s", proc.returncode, proc.stderr.strip()[:300])
        return ""
    return proc.stdout.strip()
