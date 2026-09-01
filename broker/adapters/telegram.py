"""Telegram Bot API long-poll adapter. Set TELEGRAM_BOT_TOKEN."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Iterator

from broker.models import InboundMessage, OutboundReply


class TelegramAdapter:
    name = "telegram"

    def __init__(self, token: str | None = None) -> None:
        self.token = token or os.environ.get("TELEGRAM_BOT_TOKEN", "")
        if not self.token:
            raise RuntimeError("TELEGRAM_BOT_TOKEN is required")
        self._offset = 0
        self._base = f"https://api.telegram.org/bot{self.token}"

    def _call(self, method: str, payload: dict) -> dict:
        data = urllib.parse.urlencode(payload).encode()
        req = urllib.request.Request(f"{self._base}/{method}", data=data)
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode())
        if not body.get("ok"):
            raise RuntimeError(body)
        return body

    def listen(self) -> Iterator[InboundMessage]:
        while True:
            try:
                body = self._call(
                    "getUpdates",
                    {"timeout": 50, "offset": self._offset, "allowed_updates": json.dumps(["message"])},
                )
            except (urllib.error.URLError, TimeoutError) as exc:
                print(f"[telegram] poll error: {exc}", flush=True)
                time.sleep(2)
                continue
            for update in body.get("result") or []:
                self._offset = int(update["update_id"]) + 1
                msg = update.get("message") or update.get("edited_message")
                if not msg or "text" not in msg:
                    continue
                chat = msg["chat"]
                from_user = msg.get("from") or {}
                yield InboundMessage(
                    channel=self.name,
                    sender_id=str(from_user.get("id", chat["id"])),
                    thread_id=str(chat["id"]),
                    text=str(msg["text"]),
                    timestamp=float(msg.get("date") or time.time()),
                    extra={"username": from_user.get("username"), "update_id": update["update_id"]},
                )

    def send(self, reply: OutboundReply) -> None:
        text = reply.text.strip() or "(empty reply)"
        chunks = [text[i : i + 4000] for i in range(0, len(text), 4000)] or [text]
        for chunk in chunks:
            self._call("sendMessage", {"chat_id": reply.thread_id, "text": chunk})
