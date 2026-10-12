"""Encrypted CAS records on dev; no plaintext diagnostic/credential in GitHub."""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import threading
import time
from urllib.parse import quote

import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

REPO = "WHITEDRAGONx/WHITE-HUB"
BRANCH = "dev/2026-10-10-autosell-compat"
PREFIX = "ai/incidents"
API = f"https://api.github.com/repos/{REPO}/contents/"
FIELDS = {"report", "status", "attempts", "created_at", "updated_at", "retry_at",
          "lease_until", "result", "source_commit", "source_sha"}


class StorageError(Exception):
    pass


class StorageConflict(StorageError):
    pass


def incident_key() -> bytes:
    # Independent, purpose-separated key; the master credential is never stored.
    secret = os.environ.get("WHITEAI_INCIDENT_KEY") or os.environ.get("WHITEAI_ADMIN_KEY", "")
    if len(secret) < 32:
        raise StorageError("storage_not_configured")
    return hmac.new(secret.encode(), b"whiteai/incident/aesgcm/v1", hashlib.sha256).digest()


def valid_id(job_id: str) -> bool:
    return isinstance(job_id, str) and re.fullmatch(r"[0-9a-f]{20}", job_id) is not None


def report_id(client_id: str, report: dict) -> str:
    if not isinstance(client_id, str) or not re.fullmatch(r"[A-Za-z0-9-]{8,80}", client_id):
        client_id = os.urandom(16).hex()
    material = json.dumps([client_id, report], sort_keys=True, allow_nan=False).encode()
    # Same payload/id in one UTC day reuses its record; a new day can register
    # a recurring incident. Date prefix also makes bounded discovery recent-first.
    day = f"{int(time.time() // 86400):06x}"
    return day + hmac.new(incident_key(), b"dedupe/v1/" + material, hashlib.sha256).hexdigest()[:14]


def encode(job_id: str, record: dict) -> str:
    if not valid_id(job_id) or set(record) - FIELDS:
        raise StorageError("invalid_record")
    data = json.dumps(record, ensure_ascii=False, allow_nan=False).encode()
    if len(data) > 30000:
        raise StorageError("record_too_large")
    nonce = os.urandom(12)
    encrypted = AESGCM(incident_key()).encrypt(nonce, data, job_id.encode())
    envelope = {"v": 1, "nonce": base64.b64encode(nonce).decode(),
                "ciphertext": base64.b64encode(encrypted).decode()}
    return base64.b64encode(json.dumps(envelope).encode()).decode()


def decode(job_id: str, content: str) -> dict:
    try:
        if not valid_id(job_id) or len(content) > 65000:
            raise ValueError()
        obj = json.loads(base64.b64decode(content))
        if obj["v"] != 1:
            raise ValueError()
        data = AESGCM(incident_key()).decrypt(base64.b64decode(obj["nonce"]),
                                             base64.b64decode(obj["ciphertext"]), job_id.encode())
        record = json.loads(data)
        if not isinstance(record, dict) or set(record) - FIELDS:
            raise ValueError()
        return record
    except Exception:
        raise StorageError("record_unreadable") from None


class GitHubIncidentStore:
    def __init__(self, write_lock: threading.Lock):
        self.lock = write_lock

    def headers(self):
        token = os.environ.get("GITHUB_TOKEN", "")
        if not token:
            raise StorageError("storage_not_configured")
        return {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}

    def url(self, job_id):
        if not valid_id(job_id):
            raise StorageError("invalid_job_id")
        return API + quote(f"{PREFIX}/{job_id}.json", safe="/")

    def load(self, job_id):
        try:
            response = requests.get(self.url(job_id), headers=self.headers(),
                                    params={"ref": BRANCH}, timeout=20)
            if response.status_code == 404:
                return None, None
            response.raise_for_status()
            obj = response.json()
            return decode(job_id, obj["content"]), obj["sha"]
        except StorageError:
            raise
        except Exception:
            raise StorageError("storage_read_failed") from None

    def save(self, job_id, record, sha=None):
        content = encode(job_id, record)
        body = {"message": "WHITE AI: encrypted incident checkpoint", "branch": BRANCH,
                "content": content}
        if sha:
            body["sha"] = sha
        try:
            with self.lock:
                response = requests.put(self.url(job_id), headers=self.headers(), json=body, timeout=20)
            if response.status_code in (409, 422):
                raise StorageConflict("storage_conflict")
            response.raise_for_status()
            return response.json()["content"]["sha"]
        except StorageError:
            raise
        except Exception:
            raise StorageError("storage_write_failed") from None

    def ids(self):
        try:
            response = requests.get(API + PREFIX, headers=self.headers(),
                                    params={"ref": BRANCH}, timeout=20)
            if response.status_code == 404:
                return []
            response.raise_for_status()
            return sorted([item["name"][:-5] for item in response.json()
                    if item.get("type") == "file" and item.get("name", "").endswith(".json")
                    and valid_id(item["name"][:-5])], reverse=True)[:100]
        except Exception:
            raise StorageError("storage_list_failed") from None
