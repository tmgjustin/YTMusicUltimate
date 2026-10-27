from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class Event:
    """One log line, normalised from any source."""

    ts: float
    device: str
    message: str
    program: str = ""
    severity: Optional[int] = None  # syslog severity 0 (emerg) .. 7 (debug)
    source_ip: str = ""  # address the line was received from

    def text(self) -> str:
        return f"{self.program}: {self.message}" if self.program else self.message


@dataclass
class Alert:
    rule_id: str
    severity: str  # info | warning | critical
    title: str
    device: str
    group: str = ""
    count: int = 1
    samples: List[str] = field(default_factory=list)
    detail: str = ""
    suppressed: bool = False

    @property
    def key(self) -> str:
        return f"{self.rule_id}|{self.device}|{self.group}"
