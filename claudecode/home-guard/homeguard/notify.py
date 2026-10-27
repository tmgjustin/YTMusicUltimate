"""Notification channels: Email (SMTP) and Telegram."""
from __future__ import annotations

import json
import logging
import smtplib
import ssl
import urllib.parse
import urllib.request
from email.message import EmailMessage
from typing import List, Tuple

from .config import secret

log = logging.getLogger(__name__)

TELEGRAM_LIMIT = 4000


def send_email(conf, subject: str, body: str) -> None:
    to = conf["to"] if isinstance(conf["to"], list) else [conf["to"]]
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = conf.get("from") or conf["username"]
    msg["To"] = ", ".join(to)
    msg.set_content(body)
    context = ssl.create_default_context()
    if conf.get("ssl"):
        smtp = smtplib.SMTP_SSL(conf["smtp_host"], conf["smtp_port"], timeout=30, context=context)
    else:
        smtp = smtplib.SMTP(conf["smtp_host"], conf["smtp_port"], timeout=30)
    with smtp:
        if not conf.get("ssl") and conf.get("starttls", True):
            smtp.starttls(context=context)
        if conf.get("username"):
            smtp.login(conf["username"], secret(conf, "password"))
        smtp.send_message(msg)


def _chunks(text: str, size: int) -> List[str]:
    out, current = [], ""
    for line in text.splitlines(keepends=True):
        while len(line) > size:
            if current:
                out.append(current)
                current = ""
            out.append(line[:size])
            line = line[size:]
        if len(current) + len(line) > size:
            out.append(current)
            current = ""
        current += line
    if current:
        out.append(current)
    return out


def send_telegram(conf, text: str) -> None:
    token = secret(conf, "bot_token")
    if not token or not conf.get("chat_id"):
        raise ValueError("telegram: bot_token / chat_id 未設定")
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    for chunk in _chunks(text, TELEGRAM_LIMIT):
        data = urllib.parse.urlencode({
            "chat_id": conf["chat_id"],
            "text": chunk,
            "disable_web_page_preview": "true",
        }).encode()
        with urllib.request.urlopen(url, data=data, timeout=30) as resp:
            result = json.load(resp)
        if not result.get("ok"):
            raise RuntimeError(f"telegram: {result}")


def send_all(cfg, subject: str, body: str, short_body: str) -> Tuple[int, List[str]]:
    """Send through every enabled channel. Returns (delivered count, errors)."""
    delivered, errors = 0, []
    channels = [
        ("email", lambda c: send_email(c, subject, body)),
        ("telegram", lambda c: send_telegram(c, short_body)),
    ]
    for name, send in channels:
        conf = cfg["notify"][name]
        if not conf.get("enabled"):
            continue
        try:
            send(conf)
            delivered += 1
        except Exception as exc:  # one broken channel must not block the others
            log.error("%s notification failed: %s", name, exc)
            errors.append(f"{name}: {exc}")
    return delivered, errors


def enabled_channels(cfg) -> List[str]:
    return [name for name, conf in cfg["notify"].items() if conf.get("enabled")]
