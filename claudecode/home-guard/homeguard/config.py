"""Configuration loading with defaults."""
from __future__ import annotations

import copy
import os
from typing import Any, Dict

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover - older Python
    try:
        import tomli as tomllib  # type: ignore
    except ModuleNotFoundError:
        tomllib = None  # type: ignore

SEVERITY_LEVELS = {"info": 0, "warning": 1, "critical": 2}

# Unified-log predicate for the Mac mini itself. Kept narrow on purpose:
# `log show` without a predicate returns millions of lines per hour.
DEFAULT_MAC_PREDICATE = (
    '(process == "sshd") OR (process == "sudo") OR (process == "su") '
    'OR (process == "screensharingd") OR (process == "socketfilterfw") '
    'OR (subsystem == "com.apple.xprotect") OR (process == "XProtect") '
    'OR (process == "kernel" AND messageType == fault)'
)

DEFAULTS: Dict[str, Any] = {
    "general": {
        "data_dir": "/usr/local/var/home-guard",
        "retention_days": 30,
        "learning_days": 3,
        "min_notify_severity": "warning",
    },
    "receiver": {
        "listen": "0.0.0.0",
        "udp_port": 514,
        "tcp_port": 514,
    },
    "devices": [],
    "local_mac": {
        "enabled": True,
        "name": "mac-mini",
        "predicate": DEFAULT_MAC_PREDICATE,
        "max_lookback_minutes": 120,
        "check_panics": True,
        "check_launch_items": True,
        "disk_usage_percent": 90,
    },
    "detect": {
        "trusted_networks": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fd00::/8"],
        "brute_force_threshold": 5,
        "silent_minutes": 120,
        "volume_sigma": 4.0,
        "volume_min_events": 50,
        "volume_min_samples": 24,
        "alert_cooldown_minutes": 120,
        "known_macs": {},
    },
    "rules": [],
    "notify": {
        "email": {
            "enabled": False,
            "smtp_host": "smtp.gmail.com",
            "smtp_port": 587,
            "ssl": False,
            "starttls": True,
            "username": "",
            "password": "",
            "password_env": "HOMEGUARD_SMTP_PASSWORD",
            "from": "",
            "to": [],
        },
        "telegram": {
            "enabled": False,
            "bot_token": "",
            "bot_token_env": "HOMEGUARD_TELEGRAM_TOKEN",
            "chat_id": "",
        },
    },
    "ai": {
        "enabled": False,
        "command": ["claude", "-p"],
        "timeout_seconds": 180,
        "max_sample_lines": 60,
    },
}


def _merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    out = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _merge(out[key], value)
        else:
            out[key] = value
    return out


def with_defaults(raw: Dict[str, Any]) -> Dict[str, Any]:
    cfg = _merge(DEFAULTS, raw)
    for dev in cfg["devices"]:
        ips = dev.get("ip", [])
        dev["ips"] = [ips] if isinstance(ips, str) else list(ips)
    sev = cfg["general"]["min_notify_severity"]
    if sev not in SEVERITY_LEVELS:
        raise ValueError(f"min_notify_severity must be one of {list(SEVERITY_LEVELS)}, got {sev!r}")
    return cfg


def load_config(path: str) -> Dict[str, Any]:
    if tomllib is None:
        raise SystemExit("需要 Python 3.11 以上,或先執行: pip3 install tomli")
    with open(path, "rb") as f:
        return with_defaults(tomllib.load(f))


def secret(section: Dict[str, Any], key: str) -> str:
    """Read a secret directly from config, falling back to the `<key>_env` variable."""
    value = section.get(key) or ""
    if not value and section.get(f"{key}_env"):
        value = os.environ.get(section[f"{key}_env"], "")
    return str(value)
