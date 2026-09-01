# Warp channel broker

One process. Three layers.

1. **Adapters** — Telegram / WhatsApp / stdin. Inbound becomes `{channel, sender_id, thread_id, text, timestamp}`. Outbound is channel-native again.
2. **Router** — `telegram:<chat_id>` or `whatsapp:<number>` maps to one Warp conversation token and stays mapped.
3. **Warp runner** — first message starts a run; later messages resume that token so the thread is not cold.

Sign in once with `warp-agent`. The TUI handles login. The broker only sends prompts.

## Run

```bash
# from repo root
python -m broker --channel stdin

TELEGRAM_BOT_TOKEN=... python -m broker --channel telegram

WHATSAPP_TOKEN=... WHATSAPP_PHONE_ID=... python -m broker --channel whatsapp
```

Sessions: `~/.warp-broker/sessions.json`

```json
{
  "telegram:123456": {
    "conversation_token": "…",
    "channel": "telegram",
    "thread_id": "123456"
  }
}
```
