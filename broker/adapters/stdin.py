"""Local smoke-test adapter. Type a line, get a reply."""

from __future__ import annotations

import sys
import time
from collections.abc import Iterator

from broker.models import InboundMessage, OutboundReply


class StdinAdapter:
    name = "stdin"

    def listen(self) -> Iterator[InboundMessage]:
        print("[stdin] type a message, Ctrl-D to quit", flush=True)
        for line in sys.stdin:
            text = line.strip()
            if not text:
                continue
            yield InboundMessage(
                channel=self.name,
                sender_id="local",
                thread_id="local",
                text=text,
                timestamp=time.time(),
            )

    def send(self, reply: OutboundReply) -> None:
        print(f"\n--- warp ---\n{reply.text}\n------------\n", flush=True)
