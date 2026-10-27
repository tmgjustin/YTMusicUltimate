"""Anomaly detectors: pattern rules, new login IPs / devices, volume spikes, silence."""
from __future__ import annotations

import math
import re
import time
from collections import Counter
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Pattern

from .models import Alert, Event
from .parser import extract_ip, extract_mac, extract_user, ip_in_networks
from .state import State

# Built-in rules. `threshold` = matches needed within one analysis window,
# counted per (device, group). `require_group` skips lines where the group
# (e.g. the remote IP) can't be extracted.
BUILTIN_RULES: List[Dict] = [
    {
        "id": "brute_force",
        "title": "登入失敗次數過多 (疑似暴力破解)",
        "severity": "critical",
        "group_by": "ip",
        "require_group": True,
        "threshold": None,  # detect.brute_force_threshold
        "pattern": r"(?i)(failed password|authentication fail(ure|ed)|invalid user|login (fail|incorrect)"
                   r"|failed (to )?log ?in|incorrect password|bad password|wrong password"
                   r"|authentication: failed|unauthorized login|login attempt failed)",
    },
    {
        "id": "sudo_fail",
        "title": "sudo/su 密碼錯誤",
        "severity": "warning",
        "group_by": "device",
        "threshold": 2,
        "pattern": r"(?i)(incorrect password attempt|^sudo: .*authentication failure|^su: .*(failed|incorrect|sorry))",
    },
    {
        "id": "disk_error",
        "title": "磁碟 / 檔案系統錯誤",
        "severity": "critical",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(i/o error|medium error|bad sector|smart\b.*(fail|error|warning|threshold)|uncorrectable"
                   r"|raid.*(degrad|fail|crash)|\bdegraded\b|volume .*(crash|fail)|file ?system (error|corrupt)"
                   r"|ext4-fs error|btrfs.*(error|corrupt))",
    },
    {
        "id": "overheat",
        "title": "溫度過高 / 風扇異常",
        "severity": "critical",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(overheat|over[- ]temperature|temperature .*(too high|exceed|critical)|fan .*(fail|stop|abnormal))",
    },
    {
        "id": "power",
        "title": "電源異常 / UPS 事件",
        "severity": "critical",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(power (failure|loss|outage)|on battery|battery (is )?low|ups .*(fail|alarm|shutdown))",
    },
    {
        "id": "reboot",
        "title": "裝置重新開機",
        "severity": "warning",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(system (is )?(booting|booted|started up|starting up|reboot(ed|ing)?)|\brebooted\b"
                   r"|reboot(ing)? (system|device|now)|cold ?start|linux version \d)",
    },
    {
        "id": "link_flap",
        "title": "網路連線反覆斷線",
        "severity": "warning",
        "group_by": "device",
        "threshold": 6,
        "pattern": r"(?i)(link (is |state )?(down|changed to down)|carrier lost|\bport \S+ .*\bdown\b"
                   r"|interface \S+ .*\bdown\b|wan .*(down|disconnect))",
    },
    {
        "id": "config_change",
        "title": "設定或韌體變更",
        "severity": "warning",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(config(uration)? (was |has been )?(changed|modified|saved|restored|applied)"
                   r"|firmware (upgrade|update|was updated)|factory reset"
                   r"|admin(istrator)? (password|account) (changed|created|added))",
    },
    {
        "id": "crash",
        "title": "程式當掉 / 記憶體不足",
        "severity": "warning",
        "group_by": "device",
        "threshold": 3,
        "pattern": r"(?i)(out of memory|oom[- ]killer|segfault|kernel panic|watchdog|core dumped|call trace)",
    },
    {
        "id": "intrusion",
        "title": "偵測到攻擊 / 惡意程式",
        "severity": "critical",
        "group_by": "device",
        "threshold": 1,
        "pattern": r"(?i)(port ?scan|syn ?flood|dos attack|intrusion|attack detected|threat detected"
                   r"|malware (detected|found|removed)|virus (found|detected)|xprotect.*(detect|remediat))",
    },
    {
        "id": "firewall_flood",
        "title": "大量被防火牆阻擋的連線",
        "severity": "warning",
        "group_by": "ip",
        "require_group": True,
        "threshold": 100,
        "pattern": r"(?i)(\bblock(ed)?\b|\bdrop(ped)?\b|\bdeny\b|\bdenied\b|\breject(ed)?\b)",
    },
]

LOGIN_OK_RE = re.compile(
    r"(?i)(accepted (password|publickey|keyboard-interactive)|authentication: succeeded|logged in"
    r"|login success|successfully logged|signed in|vpn .*\bconnected)"
)
NETWORK_JOIN_RE = re.compile(r"(?i)(dhcp|dnsmasq|lease|assoc|join|connected|authorized)")


@dataclass
class Rule:
    id: str
    title: str
    severity: str
    regex: Pattern
    group_by: str = "device"
    threshold: int = 1
    require_group: bool = False
    devices: Optional[Pattern] = None


def compile_rules(cfg) -> List[Rule]:
    merged: Dict[str, Dict] = {r["id"]: dict(r) for r in BUILTIN_RULES}
    for custom in cfg.get("rules", []):
        merged.setdefault(custom["id"], {"title": custom["id"], "severity": "warning"}).update(custom)
    rules = []
    for rid, r in merged.items():
        if not r.get("enabled", True) or not r.get("pattern"):
            continue
        threshold = r.get("threshold", 1)
        if threshold is None:  # built-in brute_force follows the configurable threshold
            threshold = cfg["detect"]["brute_force_threshold"]
        rules.append(Rule(
            id=rid,
            title=r["title"],
            severity=r.get("severity", "warning"),
            regex=re.compile(r["pattern"]),
            group_by=r.get("group_by", "device"),
            threshold=int(threshold),
            require_group=bool(r.get("require_group", False)),
            devices=re.compile(r["devices"]) if r.get("devices") else None,
        ))
    return rules


def _group(group_by: str, text: str) -> str:
    if group_by == "ip":
        return extract_ip(text)
    if group_by == "mac":
        return extract_mac(text)
    if group_by == "user":
        return extract_user(text)
    return ""


def apply_rules(events: Iterable[Event], rules: List[Rule]) -> List[Alert]:
    buckets: Dict[tuple, Alert] = {}
    for ev in events:
        text = ev.text()
        for rule in rules:
            if rule.devices and not rule.devices.search(ev.device):
                continue
            if not rule.regex.search(text):
                continue
            group = _group(rule.group_by, text)
            if rule.require_group and not group:
                continue
            key = (rule.id, ev.device, group)
            alert = buckets.get(key)
            if alert is None:
                alert = buckets[key] = Alert(rule.id, rule.severity, rule.title, ev.device, group, 0)
            alert.count += 1
            if len(alert.samples) < 3:
                alert.samples.append(text[:300])
    rules_by_id = {r.id: r for r in rules}
    alerts = []
    for alert in buckets.values():
        if alert.count < rules_by_id[alert.rule_id].threshold:
            continue
        if alert.group:
            user = extract_user(alert.samples[0])
            alert.detail = f"{rules_by_id[alert.rule_id].group_by}={alert.group}" + (f", user={user}" if user else "")
        alerts.append(alert)
    return alerts


def detect_new_login_ips(events, state: State, cfg, learning: bool, now: float) -> List[Alert]:
    trusted = cfg["detect"]["trusted_networks"]
    alerts = []
    for ev in events:
        text = ev.text()
        if not LOGIN_OK_RE.search(text):
            continue
        ip = extract_ip(text)
        if not ip or not state.add_known("login_ip", ev.device, ip, now) or learning:
            continue
        internal = ip_in_networks(ip, trusted)
        user = extract_user(text)
        alerts.append(Alert(
            "new_login_ip", "info" if internal else "warning",
            "從新的 IP 登入成功" + ("" if internal else " (外部網路)"),
            ev.device, ip, 1, [text[:300]],
            f"ip={ip}" + (f", user={user}" if user else ""),
        ))
    return alerts


def detect_new_macs(events, state: State, cfg, learning: bool, now: float) -> List[Alert]:
    known = {k.lower().replace("-", ":"): v for k, v in cfg["detect"]["known_macs"].items()}
    alerts = []
    for ev in events:
        text = ev.text()
        if not NETWORK_JOIN_RE.search(text):
            continue
        mac = extract_mac(text)
        if not mac or mac in known or not state.add_known("mac", "*", mac, now) or learning:
            continue
        ip = extract_ip(text)
        alerts.append(Alert(
            "new_device", "warning", "偵測到新裝置連上網路", ev.device, mac, 1, [text[:300]],
            f"mac={mac}" + (f", ip={ip}" if ip else ""),
        ))
    return alerts


def detect_unknown_senders(events, state: State, now: float) -> List[Alert]:
    alerts = []
    for device in sorted({ev.device for ev in events if ev.device.startswith("unknown-")}):
        if state.add_known("sender", "*", device, now):
            alerts.append(Alert(
                "unknown_sender", "info", "收到未登記裝置送來的 log", device, "", 1, [],
                "可在 config.toml 的 [[devices]] 加上名稱",
            ))
    return alerts


def _normalise(text: str) -> str:
    return re.sub(r"\d+", "#", text)[:160]


def detect_volume(events, state: State, cfg, device_names: Iterable[str], now: float, minutes: float) -> List[Alert]:
    """Flag devices logging far more than usual for this hour of day."""
    det = cfg["detect"]
    hour = time.localtime(now).tm_hour
    counts = Counter(ev.device for ev in events)
    alerts = []
    for device in sorted(set(counts) | set(device_names)):
        count = counts.get(device, 0)
        rate = count / minutes
        n, mean, m2 = state.volume_stats(device, hour)
        if n >= det["volume_min_samples"]:
            std = math.sqrt(m2 / (n - 1)) if n > 1 else 0.0
            std = max(std, mean * 0.25, 0.1)
            if count >= det["volume_min_events"] and rate > mean + det["volume_sigma"] * std:
                top = Counter(_normalise(ev.text()) for ev in events if ev.device == device).most_common(3)
                alerts.append(Alert(
                    "volume_spike", "warning", "log 數量異常暴增", device, "", count,
                    [f"{c}× {t}" for t, c in top],
                    f"{count} 筆 / {minutes:.0f} 分鐘 (此時段平常約 {mean * minutes:.0f} 筆)",
                ))
                continue  # keep the spike out of the baseline
        state.update_volume(device, hour, rate)
    return alerts


def detect_silence(state: State, cfg, now: float, first_run: float) -> List[Alert]:
    default = cfg["detect"]["silent_minutes"]
    last_seen = state.last_seen()
    alerts = []
    for dev in cfg["devices"]:
        limit = dev.get("silent_minutes", default)
        if not limit:
            continue
        last = last_seen.get(dev["name"])
        if now - (last or first_run) > limit * 60:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(last)) if last else "從未收到"
            alerts.append(Alert(
                "device_silent", "warning", "裝置沒有送出 log (可能離線或設定跑掉)", dev["name"], "", 1, [],
                f"最後收到: {when},門檻 {limit} 分鐘",
            ))
    return alerts
