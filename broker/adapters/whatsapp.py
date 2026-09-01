"""WhatsApp Cloud API webhook stub.

Set WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, WHATSAPP_VERIFY_TOKEN.
"""

from __future__ import annotations

import json
import os
import queue
import threading
import time
import urllib.request
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from broker.models import InboundMessage, OutboundReply


class WhatsAppAdapter:
    name = "whatsapp"

    def __init__(self, host: str = "0.0.0.0", port: int = 8787) -> None:
        self.token = os.environ.get("WHATSAPP_TOKEN", "")
        self.phone_id = os.environ.get("WHATSAPP_PHONE_ID", "")
        self.verify = os.environ.get("WHATSAPP_VERIFY_TOKEN", "warp-broker")
        self.host = host
        self.port = port
        self._q: queue.Queue[InboundMessage] = queue.Queue()

    def listen(self) -> Iterator[InboundMessage]:
        adapter = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, fmt: str, *args) -> None:
                return

            def do_GET(self) -> None:
                from urllib.parse import parse_qs, urlparse

                qs = parse_qs(urlparse(self.path).query)
                mode = (qs.get("hub.mode") or [""])[0]
                token = (qs.get("hub.verify_token") or [""])[0]
                challenge = (qs.get("hub.challenge") or [""])[0]
                if mode == "subscribe" and token == adapter.verify:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(challenge.encode())
                    return
                self.send_response(403)
                self.end_headers()

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length)
                try:
                    payload = json.loads(raw.decode() or "{}")
                except json.JSONDecodeError:
                    self.send_response(400)
                    self.end_headers()
                    return
                for entry in payload.get("entry") or []:
                    for change in entry.get("changes") or []:
                        value = change.get("value") or {}
                        for msg in value.get("messages") or []:
                            if msg.get("type") != "text":
                                continue
                            text = ((msg.get("text") or {}).get("body")) or ""
                            sender = str(msg.get("from") or "")
                            adapter._q.put(
                                InboundMessage(
                                    channel=adapter.name,
                                    sender_id=sender,
                                    thread_id=sender,
                                    text=text,
                                    timestamp=float(msg.get("timestamp") or time.time()),
                                    extra={"id": msg.get("id")},
                                )
                            )
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")

        httpd = ThreadingHTTPServer((self.host, self.port), Handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        print(f"[whatsapp] webhook on http://{self.host}:{self.port}/", flush=True)
        while True:
            yield self._q.get()

    def send(self, reply: OutboundReply) -> None:
        if not self.token or not self.phone_id:
            print("[whatsapp] missing WHATSAPP_TOKEN / WHATSAPP_PHONE_ID; printing reply")
            print(reply.text)
            return
        url = f"https://graph.facebook.com/v21.0/{self.phone_id}/messages"
        payload = json.dumps(
            {
                "messaging_product": "whatsapp",
                "to": reply.thread_id,
                "type": "text",
                "text": {"body": reply.text[:4096]},
            }
        ).encode()
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp.read()
