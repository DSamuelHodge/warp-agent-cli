"""Common inbound/outbound shapes every channel adapter uses."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class InboundMessage:
    channel: str
    sender_id: str
    thread_id: str
    text: str
    timestamp: float
    extra: dict[str, Any] = field(default_factory=dict)

    @property
    def session_key(self) -> str:
        return f"{self.channel}:{self.thread_id}"


@dataclass(frozen=True)
class OutboundReply:
    channel: str
    thread_id: str
    text: str
    extra: dict[str, Any] = field(default_factory=dict)
