from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Protocol

from broker.models import InboundMessage, OutboundReply


class ChannelAdapter(Protocol):
    name: str

    def listen(self) -> Iterator[InboundMessage]:
        """Yield normalized inbound messages."""

    def send(self, reply: OutboundReply) -> None:
        """Render an agent reply in this channel's format and deliver it."""


Handler = Callable[[InboundMessage], OutboundReply]
