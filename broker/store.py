"""Persistent map: channel thread -> Warp conversation token."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any


class SessionStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._data: dict[str, dict[str, Any]] = {}
        self.load()

    def load(self) -> None:
        if self.path.exists():
            self._data = json.loads(self.path.read_text())
        else:
            self._data = {}

    def save(self) -> None:
        self.path.write_text(json.dumps(self._data, indent=2, sort_keys=True))

    def get(self, session_key: str) -> dict[str, Any] | None:
        row = self._data.get(session_key)
        return dict(row) if row else None

    def conversation_token(self, session_key: str) -> str | None:
        row = self.get(session_key)
        if not row:
            return None
        token = row.get("conversation_token")
        return str(token) if token else None

    def upsert(
        self,
        session_key: str,
        *,
        conversation_token: str | None = None,
        channel: str | None = None,
        thread_id: str | None = None,
    ) -> dict[str, Any]:
        row = self._data.get(session_key, {})
        now = time.time()
        if "created_at" not in row:
            row["created_at"] = now
        row["updated_at"] = now
        if conversation_token:
            row["conversation_token"] = conversation_token
        if channel:
            row["channel"] = channel
        if thread_id:
            row["thread_id"] = thread_id
        self._data[session_key] = row
        self.save()
        return dict(row)
