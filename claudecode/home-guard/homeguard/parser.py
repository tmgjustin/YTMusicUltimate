"""Parsing helpers: syslog lines, IPs, MACs, user names."""
from __future__ import annotations

import ipaddress
import re
from typing import Optional, Tuple

PRI_RE = re.compile(r"^<(\d{1,3})>")
RFC5424_RE = re.compile(r"^1 (\S+) (\S+) (\S+) (\S+) (\S+) (-|(?:\[.*?\])+) ?(.*)$", re.S)
BSD_TS_RE = re.compile(r"^[A-Z][a-z]{2} +\d{1,2} \d\d:\d\d:\d\d(?:\.\d+)? (?:\d{4} )?")
ISO_TS_RE = re.compile(r"^\d{4}-\d\d-\d\d[T ]\d\d:\d\d:\d\d\S* ")
HOST_TAG_RE = re.compile(r"^(\S+) ([\w\-./@()]+?)(?:\[\d+\])?: ?(.*)$", re.S)
TAG_RE = re.compile(r"^([\w\-./@()]+?)(?:\[\d+\])?: ?(.*)$", re.S)

IP_KEYED_RE = re.compile(
    r"(?i)(?:\bfrom|rhost=|\bsrc=|source[: ]|client[: ]|\bip[: =]|address[: ]|viewer address: )"
    r"\s*\[?((?:\d{1,3}\.){3}\d{1,3})"
)
IP_ANY_RE = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])")
MAC_RE = re.compile(r"(?i)(?<![0-9a-f:-])([0-9a-f]{2}(?::[0-9a-f]{2}){5}|[0-9a-f]{2}(?:-[0-9a-f]{2}){5})(?![0-9a-f:-])")
USER_RE = re.compile(r"(?i)(?:for (?:invalid user )?|\buser[= ]|\baccount )['\"]?([\w.\-@]+)")

SyslogParts = Tuple[Optional[int], Optional[int], str, str]


def parse_syslog(raw: str) -> SyslogParts:
    """Return (facility, severity, program, message) for an RFC 3164/5424 line."""
    raw = raw.strip()
    facility = severity = None
    m = PRI_RE.match(raw)
    if m:
        pri = int(m.group(1))
        facility, severity = pri >> 3, pri & 7
        raw = raw[m.end():]

    m = RFC5424_RE.match(raw)
    if m:
        app, msg = m.group(3), m.group(7)
        if msg.startswith("\ufeff"):
            msg = msg[1:]
        return facility, severity, "" if app == "-" else app, msg

    raw = BSD_TS_RE.sub("", raw, count=1)
    raw = ISO_TS_RE.sub("", raw, count=1)
    m = HOST_TAG_RE.match(raw)
    if m and ":" not in m.group(1):
        return facility, severity, m.group(2), m.group(3)
    m = TAG_RE.match(raw)
    if m:
        return facility, severity, m.group(1), m.group(2)
    return facility, severity, "", raw


def _valid_ip(s: str) -> bool:
    try:
        ipaddress.ip_address(s)
        return True
    except ValueError:
        return False


def extract_ip(text: str) -> str:
    """Best guess at the remote address mentioned in a log line."""
    for regex in (IP_KEYED_RE, IP_ANY_RE):
        for m in regex.finditer(text):
            if _valid_ip(m.group(1)):
                return m.group(1)
    return ""


def extract_mac(text: str) -> str:
    m = MAC_RE.search(text)
    return m.group(1).lower().replace("-", ":") if m else ""


def extract_user(text: str) -> str:
    m = USER_RE.search(text)
    return m.group(1) if m else ""


def ip_in_networks(ip: str, networks) -> bool:
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    for net in networks:
        try:
            if addr in ipaddress.ip_network(net, strict=False):
                return True
        except (ValueError, TypeError):
            continue
    return False
