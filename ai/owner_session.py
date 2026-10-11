"""Stateless, time-limited owner pairing for the private WHITE AI development client.

No secrets, tokens, or session registry are stored in GitHub or Render disk.
The server verifies an HMAC signed with WHITEAI_ADMIN_KEY. Rotating that key,
or advancing WHITEAI_SESSION_NOT_BEFORE, invalidates existing sessions.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import time

SESSION_TTL_SECONDS = 30 * 24 * 60 * 60
SESSION_VERSION = "wa1"


def issue_owner_session(admin_key: str, *, now: int | None = None) -> tuple[str, int]:
    if not isinstance(admin_key, str) or len(admin_key) < 32:
        raise ValueError("Owner signing key not configured")
    issued = int(time.time() if now is None else now)
    expires = issued + SESSION_TTL_SECONDS
    nonce = secrets.token_urlsafe(24)
    payload = f"{SESSION_VERSION}.{issued}.{expires}.{nonce}"
    signature = hmac.new(admin_key.encode("utf-8"), payload.encode("ascii"),
                         hashlib.sha256).hexdigest()
    return f"{payload}.{signature}", expires


def verify_owner_session(token: str, admin_key: str, *,
                         not_before: int = 0,
                         now: int | None = None) -> bool:
    if not isinstance(token, str) or len(token) > 256 or len(token) < 100:
        return False
    if not isinstance(admin_key, str) or len(admin_key) < 32:
        return False
    parts = token.split(".")
    if len(parts) != 5 or parts[0] != SESSION_VERSION:
        return False
    _, issued_str, expires_str, nonce, signature = parts
    if (not issued_str.isascii() or not issued_str.isdecimal()
            or not expires_str.isascii() or not expires_str.isdecimal()
            or len(issued_str) > 12 or len(expires_str) > 12
            or len(nonce) < 20 or len(nonce) > 48
            or not all(c.isascii() and (c.isalnum() or c in "_-") for c in nonce)
            or len(signature) != 64
            or not all(c in "0123456789abcdef" for c in signature)):
        return False
    issued, expires = int(issued_str), int(expires_str)
    current = int(time.time() if now is None else now)
    if (issued < not_before or issued > current + 60 or
            expires <= current or expires <= issued or
            expires - issued > SESSION_TTL_SECONDS):
        return False
    payload = ".".join(parts[:4])
    wanted = hmac.new(admin_key.encode("utf-8"), payload.encode("ascii"),
                      hashlib.sha256).hexdigest()
    return hmac.compare_digest(wanted, signature)
