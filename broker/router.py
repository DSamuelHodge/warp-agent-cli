"""Layer 2: map an external thread onto one Warp conversation."""

from __future__ import annotations

from broker.models import InboundMessage, OutboundReply
from broker.store import SessionStore
from broker.warp_runner import WarpRunner


class Router:
    def __init__(self, store: SessionStore, runner: WarpRunner) -> None:
        self.store = store
        self.runner = runner

    def handle(self, msg: InboundMessage) -> OutboundReply:
        key = msg.session_key
        self.store.upsert(key, channel=msg.channel, thread_id=msg.thread_id)
        token = self.store.conversation_token(key)
        text, new_token = self.runner.run(msg.text, token)
        if new_token:
            self.store.upsert(key, conversation_token=new_token)
        return OutboundReply(channel=msg.channel, thread_id=msg.thread_id, text=text or "(no output)")
