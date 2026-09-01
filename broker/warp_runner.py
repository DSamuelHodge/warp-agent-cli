"""Layer 3: run Warp and capture a resume token so threads stay warm."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

RESUME_RE = re.compile(r"warp\s+--resume\s+(\S+)")


class WarpRunner:
    def __init__(self, cwd: str | None = None, bin_name: str | None = None) -> None:
        self.cwd = cwd or os.environ.get("WARP_BROKER_CWD") or os.getcwd()
        self.bin = bin_name or self._resolve_bin()

    def _resolve_bin(self) -> str:
        for name in ("warp-agent", "warp", "oz"):
            path = shutil.which(name)
            if path:
                return path
        return "warp-agent"

    def run(self, prompt: str, conversation_token: str | None = None) -> tuple[str, str | None]:
        """Return (reply_text, conversation_token)."""
        env = os.environ.copy()
        env.setdefault("TERM", "xterm-256color")

        if conversation_token:
            text, token = self._run_resume(prompt, conversation_token, env)
        else:
            text, token = self._run_fresh(prompt, env)
        return text.strip(), token or conversation_token

    def _run_fresh(self, prompt: str, env: dict[str, str]) -> tuple[str, str | None]:
        for argv in (
            [self.bin, "agent", "run", "--prompt", prompt],
            [self.bin, "run", "--prompt", prompt],
        ):
            if Path(self.bin).name in {"oz", "warp"} or self.bin.endswith("/oz") or self.bin.endswith("/warp"):
                result = self._exec(argv, env)
                if result.returncode == 0 or result.stdout.strip():
                    return result.stdout or result.stderr, self._token(result.stdout + result.stderr)
        result = self._exec([self.bin, prompt], env)
        combined = (result.stdout or "") + (result.stderr or "")
        return result.stdout or result.stderr, self._token(combined)

    def _run_resume(self, prompt: str, token: str, env: dict[str, str]) -> tuple[str, str | None]:
        for argv in (
            [self.bin, "agent", "run", "--prompt", prompt, "--resume", token],
            [self.bin, "--resume", token, prompt],
            [self.bin, "agent", "run", "--prompt", prompt],
        ):
            result = self._exec(argv, env)
            combined = (result.stdout or "") + (result.stderr or "")
            if result.returncode == 0 or result.stdout.strip():
                return result.stdout or result.stderr, self._token(combined) or token
        return combined, token

    def _exec(self, argv: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                argv,
                cwd=self.cwd,
                env=env,
                text=True,
                capture_output=True,
                timeout=int(os.environ.get("WARP_BROKER_TIMEOUT", "600")),
            )
        except FileNotFoundError:
            return subprocess.CompletedProcess(argv, 127, "", f"missing binary: {argv[0]}")
        except subprocess.TimeoutExpired as exc:
            out = (exc.stdout or "") + (exc.stderr or "")
            return subprocess.CompletedProcess(argv, 124, out, "warp timed out")

    @staticmethod
    def _token(blob: str) -> str | None:
        match = RESUME_RE.search(blob or "")
        return match.group(1).strip() if match else None
