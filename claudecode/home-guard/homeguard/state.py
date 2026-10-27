"""Persistent state (offsets, baselines, known values, alert cooldowns) in SQLite."""
from __future__ import annotations

import os
import sqlite3
from typing import Dict, Optional, Tuple

from .models import Alert

SCHEMA = """
CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE IF NOT EXISTS offsets (path TEXT PRIMARY KEY, inode INTEGER, offset INTEGER);
CREATE TABLE IF NOT EXISTS devices (name TEXT PRIMARY KEY, last_seen REAL);
CREATE TABLE IF NOT EXISTS known (
    kind TEXT, device TEXT, value TEXT, first_seen REAL,
    PRIMARY KEY (kind, device, value)
);
CREATE TABLE IF NOT EXISTS volume (
    device TEXT, hour INTEGER, n INTEGER, mean REAL, m2 REAL,
    PRIMARY KEY (device, hour)
);
CREATE TABLE IF NOT EXISTS alerts (key TEXT PRIMARY KEY, last_sent REAL);
CREATE TABLE IF NOT EXISTS alert_log (
    ts REAL, severity TEXT, rule_id TEXT, device TEXT, grp TEXT, title TEXT, count INTEGER
);
"""


class State:
    def __init__(self, path: str):
        self.db = sqlite3.connect(str(path))
        self.db.executescript(SCHEMA)

    def commit(self) -> None:
        self.db.commit()

    def close(self) -> None:
        self.db.commit()
        self.db.close()

    # key/value
    def get_kv(self, key: str) -> Optional[str]:
        row = self.db.execute("SELECT value FROM kv WHERE key=?", (key,)).fetchone()
        return row[0] if row else None

    def get_float(self, key: str) -> Optional[float]:
        value = self.get_kv(key)
        return float(value) if value is not None else None

    def set_kv(self, key: str, value) -> None:
        self.db.execute("INSERT OR REPLACE INTO kv VALUES (?, ?)", (key, str(value)))

    # file offsets
    def get_offset(self, path: str) -> Tuple[Optional[int], int]:
        row = self.db.execute("SELECT inode, offset FROM offsets WHERE path=?", (path,)).fetchone()
        return (row[0], row[1]) if row else (None, 0)

    def set_offset(self, path: str, inode: int, offset: int) -> None:
        self.db.execute("INSERT OR REPLACE INTO offsets VALUES (?, ?, ?)", (path, inode, offset))

    # device last-seen
    def touch_device(self, name: str, ts: float) -> None:
        self.db.execute(
            "INSERT INTO devices VALUES (?, ?) "
            "ON CONFLICT(name) DO UPDATE SET last_seen=max(last_seen, excluded.last_seen)",
            (name, ts),
        )

    def last_seen(self) -> Dict[str, float]:
        return dict(self.db.execute("SELECT name, last_seen FROM devices"))

    # known values (login IPs, MACs, launch items, ...)
    def add_known(self, kind: str, device: str, value: str, now: float) -> bool:
        """Remember a value; returns True if it was not known before."""
        cur = self.db.execute(
            "INSERT OR IGNORE INTO known VALUES (?, ?, ?, ?)", (kind, device, value, now)
        )
        return cur.rowcount == 1

    # volume baseline (Welford running mean/variance per device and hour of day)
    def volume_stats(self, device: str, hour: int) -> Tuple[int, float, float]:
        row = self.db.execute(
            "SELECT n, mean, m2 FROM volume WHERE device=? AND hour=?", (device, hour)
        ).fetchone()
        return row if row else (0, 0.0, 0.0)

    def update_volume(self, device: str, hour: int, x: float) -> None:
        n, mean, m2 = self.volume_stats(device, hour)
        n += 1
        delta = x - mean
        mean += delta / n
        m2 += delta * (x - mean)
        self.db.execute("INSERT OR REPLACE INTO volume VALUES (?, ?, ?, ?, ?)", (device, hour, n, mean, m2))

    # alert cooldowns and history
    def alert_last_sent(self, key: str) -> Optional[float]:
        row = self.db.execute("SELECT last_sent FROM alerts WHERE key=?", (key,)).fetchone()
        return row[0] if row else None

    def mark_alert_sent(self, key: str, ts: float) -> None:
        self.db.execute("INSERT OR REPLACE INTO alerts VALUES (?, ?)", (key, ts))

    def log_alert(self, ts: float, alert: Alert) -> None:
        self.db.execute(
            "INSERT INTO alert_log VALUES (?, ?, ?, ?, ?, ?, ?)",
            (ts, alert.severity, alert.rule_id, alert.device, alert.group, alert.title, alert.count),
        )

    def prune(self, cutoff: float) -> None:
        self.db.execute("DELETE FROM alert_log WHERE ts < ?", (cutoff,))
        self.db.execute("DELETE FROM alerts WHERE last_sent < ?", (cutoff,))
        for (path,) in self.db.execute("SELECT path FROM offsets").fetchall():
            if not os.path.exists(path):
                self.db.execute("DELETE FROM offsets WHERE path=?", (path,))
