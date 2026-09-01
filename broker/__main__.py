"""Single broker process.

  python -m broker --channel stdin
  TELEGRAM_BOT_TOKEN=... python -m broker --channel telegram
  python -m broker --channel whatsapp
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from broker.adapters.stdin import StdinAdapter
from broker.adapters.telegram import TelegramAdapter
from broker.adapters.whatsapp import WhatsAppAdapter
from broker.router import Router
from broker.store import SessionStore
from broker.warp_runner import WarpRunner


def build_adapter(name: str):
    if name == "telegram":
        return TelegramAdapter()
    if name == "whatsapp":
        return WhatsAppAdapter(port=int(os.environ.get("WHATSAPP_PORT", "8787")))
    if name == "stdin":
        return StdinAdapter()
    raise SystemExit(f"unknown channel: {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Warp channel broker")
    parser.add_argument("--channel", default="stdin", choices=("stdin", "telegram", "whatsapp"))
    parser.add_argument(
        "--store",
        default=os.environ.get("WARP_BROKER_STORE", str(Path.home() / ".warp-broker" / "sessions.json")),
    )
    parser.add_argument("--cwd", default=os.environ.get("WARP_BROKER_CWD"))
    args = parser.parse_args()

    adapter = build_adapter(args.channel)
    router = Router(SessionStore(Path(args.store)), WarpRunner(cwd=args.cwd))
    print(f"[broker] channel={adapter.name} store={args.store}", flush=True)

    for inbound in adapter.listen():
        if not inbound.text.strip():
            continue
        print(f"[broker] {inbound.session_key}: {inbound.text[:80]}", flush=True)
        reply = router.handle(inbound)
        adapter.send(reply)


if __name__ == "__main__":
    main()
