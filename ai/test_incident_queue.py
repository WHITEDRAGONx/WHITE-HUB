"""Durable queue tests: authenticated encryption, restart, CAS, HTTP, no external calls."""
import copy
import json
import os
import threading
import unittest
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from ai import server
from ai.incident_store import encode, decode, report_id, GitHubIncidentStore, StorageError, StorageConflict
from ai.owner_session import issue_owner_session

ENV = {"WHITEAI_ADMIN_KEY": "dummy-owner-key-" + "x" * 40,
       "WHITEAI_INGEST_KEY": "dummy-ingest-" + "z" * 20,
       "GEMINI_API_KEY": "dummy-gemini-test", "GITHUB_TOKEN": "dummy-github-test",
       "WHITEAI_AUTOPATCH_ENABLED": "0", "WHITEAI_INCIDENT_KEY": ""}
REPORT = {"id": "test-report-id-1234", "module": "StandFarm", "category": "stall",
          "reason": "Arrow dialogue timed out", "context": {"recent": []}}
JOB = "a" * 20


class MemoryStore:
    def __init__(self):
        self.data = {}
        self.trace = []

    def load(self, job):
        self.trace.append("load")
        if job not in self.data:
            return None, None
        content, sha = self.data[job]
        return decode(job, content), sha

    def save(self, job, record, sha=None):
        current = self.data.get(job, (None, None))[1]
        if current != sha:
            raise StorageConflict("conflict")
        content = encode(job, record)
        new_sha = str(int(current or 0) + 1)
        self.data[job] = (content, new_sha)
        self.trace.append(record["status"])
        return new_sha

    def ids(self):
        return list(self.data)


class IncidentQueueTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, ENV); self.env.start(); self.addCleanup(self.env.stop)
        self.store = MemoryStore()
        self.storage = patch.object(server, "_incident_store", self.store); self.storage.start(); self.addCleanup(self.storage.stop)
        server._jobs.clear(); server._recent.clear()
        self.client = TestClient(server.app)
        self.now = 1000
        timer = patch("ai.server.time.time", side_effect=lambda: self.now); timer.start(); self.addCleanup(timer.stop)
        get = patch("ai.server.requests.get", return_value=Mock(json=lambda: {"object": {"sha": "b" * 40}})); get.start(); self.addCleanup(get.stop)
        read = patch("ai.server.read_github_file", return_value=("local a = 1", "blob")); self.read = read.start(); self.addCleanup(read.stop)
        publish = patch("ai.server.publish_review_artifact", return_value="https://github.com/example/proposal"); self.publish = publish.start(); self.addCleanup(publish.stop)
        self.headers = {"X-WhiteAI-Key": ENV["WHITEAI_INGEST_KEY"]}

    def queued(self, job=JOB):
        record = {"report": server.clean_report(REPORT), "status": "queued", "attempts": 0,
                  "created_at": self.now, "updated_at": self.now, "lease_until": 0,
                  "retry_at": None, "result": {}}
        self.store.save(job, record)
        return record

    def failure(self, code="gemini_unavailable"):
        return server.GeminiAPIError(code, "safe test hint")

    def test_ciphertext_roundtrip_unique_nonce_and_no_plaintext(self):
        record = self.queued()
        a, b = encode(JOB, record), encode(JOB, record)
        self.assertNotEqual(a, b)
        self.assertEqual(decode(JOB, a), record)
        import base64
        envelope = base64.b64decode(a).decode()
        self.assertNotIn(REPORT["reason"], envelope)
        self.assertNotIn(ENV["WHITEAI_ADMIN_KEY"], envelope)
        with self.assertRaises(StorageError): decode("c" * 20, a)
        with patch.dict(os.environ, {"WHITEAI_ADMIN_KEY": "different-test-key" * 4}):
            with self.assertRaises(StorageError): decode(JOB, a)

    def test_authority_cannot_be_serialized(self):
        record = self.queued(); record["owner_autopatch"] = True
        with self.assertRaises(StorageError): encode(JOB, record)

    def test_known_secret_and_session_scrubbing_before_storage(self):
        report = copy.deepcopy(REPORT)
        report["reason"] = "X-WhiteAI-Admin-Key: " + ENV["WHITEAI_ADMIN_KEY"]
        token, _ = issue_owner_session(ENV["WHITEAI_ADMIN_KEY"], now=1000)
        report["context"]["recent"] = [{"message": "Authorization: Bearer " + token,
                                         "module": "StandFarm", "level": "WARN"}]
        report["authorization"] = token
        clean = json.dumps(server.clean_report(report))
        self.assertNotIn(token, clean); self.assertNotIn(ENV["WHITEAI_ADMIN_KEY"], clean)
        self.assertNotIn("wa1.", clean)

    def test_stand_routing_read_only(self):
        path = server.allowed_module_path(server.clean_report(REPORT))
        self.assertEqual(path, "StandFarm.lua")
        self.assertNotIn(path, server.PATCH_ALLOWLIST)

    def test_ack_only_after_saved_and_source_pinned(self):
        def ask(*args):
            self.assertIn("queued", self.store.trace)
            return {"file": "StandFarm.lua", "summary": "diagnosis", "old_text": "", "new_text": ""}
        with patch("ai.server.ask_ai", side_effect=ask):
            response = self.client.post("/reports", json=REPORT, headers=self.headers)
        self.assertEqual(response.status_code, 202)
        job = response.json()["job_id"]
        record, _ = self.store.load(job)
        self.assertEqual(record["status"], "proposal_ready")
        self.assertEqual(record["source_commit"], "b" * 40)
        self.read.assert_called_with("StandFarm.lua", "b" * 40)

    def test_failed_storage_not_acknowledged_or_analyzed(self):
        with patch.object(self.store, "save", side_effect=StorageError("failure")), patch("ai.server.ask_ai") as ask:
            response = self.client.post("/reports", json=REPORT, headers=self.headers)
        self.assertEqual(response.status_code, 503); ask.assert_not_called()

    def test_unconfirmed_branch_conflict_not_acknowledged(self):
        with patch.object(self.store, "save", side_effect=StorageConflict("branch")), patch("ai.server.ask_ai") as ask:
            response = self.client.post("/reports", json=REPORT, headers=self.headers)
        self.assertEqual(response.status_code, 503); ask.assert_not_called()

    def test_pending_retry_reloads_changed_source_revision(self):
        self.queued()
        with patch("ai.server.ask_ai", side_effect=self.failure()): server.process_saved_job(JOB)
        self.now = 1061
        with patch("ai.server.requests.get", return_value=Mock(json=lambda: {"object": {"sha": "c" * 40}})), patch("ai.server.ask_ai", return_value={"file": "StandFarm.lua", "summary": "safe"}):
            server.process_saved_job(JOB)
        self.assertEqual(self.store.load(JOB)[0]["source_commit"], "c" * 40)
        self.read.assert_called_with("StandFarm.lua", "c" * 40)

    def test_manual_retry_obeys_cooldown_and_cap(self):
        self.queued()
        headers = {"X-WhiteAI-Admin-Key": ENV["WHITEAI_ADMIN_KEY"]}
        with patch("ai.server.ask_ai", side_effect=self.failure()): server.process_saved_job(JOB)
        response = self.client.post(f"/jobs/{JOB}/retry", headers=headers)
        self.assertEqual(response.status_code, 409)
        server._recent.clear(); self.now = 1061
        with patch("ai.server.ask_ai", side_effect=self.failure()), patch("ai.server.attempt_dev_commit") as commit:
            response = self.client.post(f"/jobs/{JOB}/retry", headers=headers)
        self.assertEqual(response.status_code, 202); commit.assert_not_called()
        server._recent.clear(); self.now = 1362
        with patch("ai.server.ask_ai", side_effect=self.failure()): server.process_saved_job(JOB)
        self.assertEqual(self.client.post(f"/jobs/{JOB}/retry", headers=headers).status_code, 409)

    def test_restart_retry_preserves_report_and_never_replays_patch(self):
        self.queued()
        with patch("ai.server.ask_ai", side_effect=self.failure()): server.process_saved_job(JOB)
        record, _ = self.store.load(JOB)
        self.assertEqual(record["status"], "waiting_retry")
        self.assertEqual(record["report"]["reason"], REPORT["reason"])
        server._jobs.clear(); self.now = 1061
        with patch("ai.server.ask_ai", return_value={"file": "StandFarm.lua", "summary": "safe"}), patch("ai.server.attempt_dev_commit") as commit:
            server.process_saved_job(JOB, owner_autopatch=True)
        commit.assert_not_called()
        self.assertEqual(self.store.load(JOB)[0]["status"], "proposal_ready")
        self.assertEqual(server._jobs[JOB]["auto_patch"]["state"], "disabled")

    def test_max_three_attempts_and_cooldown(self):
        self.queued()
        with patch("ai.server.ask_ai", side_effect=self.failure()) as ask:
            server.process_saved_job(JOB); server.process_saved_job(JOB)
            self.assertEqual(ask.call_count, 1)
            self.now = 1061; server.process_saved_job(JOB)
            self.now = 1362; server.process_saved_job(JOB); server.process_saved_job(JOB)
            self.assertEqual(ask.call_count, 3)
        self.assertEqual(self.store.load(JOB)[0]["status"], "retry_exhausted")

    def test_nontransient_failure_not_retried(self):
        self.queued()
        with patch("ai.server.ask_ai", side_effect=self.failure("gemini_auth_error")) as ask:
            server.process_saved_job(JOB); self.now += 1000; server.process_saved_job(JOB)
        self.assertEqual(ask.call_count, 1)
        self.assertEqual(self.store.load(JOB)[0]["status"], "failed")

    def test_cas_conflict_and_live_lease_prevent_analysis(self):
        record = self.queued(); record["status"] = "running"; record["lease_until"] = 1100
        self.store.save(JOB, record, "1")
        with patch("ai.server.ask_ai") as ask:
            server.process_saved_job(JOB); ask.assert_not_called()
        self.now = 1101
        with patch.object(self.store, "save", side_effect=StorageConflict("lease")), patch("ai.server.ask_ai") as ask:
            server.process_saved_job(JOB); ask.assert_not_called()

    def test_duplicate_report_same_job_not_analyzed_twice(self):
        with patch("ai.server.ask_ai", side_effect=self.failure()) as ask:
            a = self.client.post("/reports", json=REPORT, headers=self.headers)
            server._recent.clear()
            b = self.client.post("/reports", json=REPORT, headers=self.headers)
        self.assertEqual(a.json()["job_id"], b.json()["job_id"])
        self.assertTrue(b.json()["duplicate"]); self.assertEqual(ask.call_count, 1)

    def test_retry_and_recovery_require_owner_not_ingest(self):
        self.queued()
        self.assertEqual(self.client.get("/incidents", headers=self.headers).status_code, 403)
        self.assertEqual(self.client.post(f"/jobs/{JOB}/retry", headers=self.headers).status_code, 403)
        token, _ = issue_owner_session(ENV["WHITEAI_ADMIN_KEY"], now=1000)
        response = self.client.get("/incidents", headers={"X-WhiteAI-Session": token})
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("report", response.text)
        self.assertEqual(response.json()["incidents"][0]["job_id"], JOB)

    def test_recovered_queued_job_get_schedules_review_only(self):
        self.queued(); server._jobs.clear()
        with patch("ai.server.ask_ai", return_value={"file": "StandFarm.lua", "summary": "safe"}), patch("ai.server.attempt_dev_commit") as commit:
            response = self.client.get(f"/jobs/{JOB}", headers=self.headers)
        self.assertEqual(response.status_code, 200); commit.assert_not_called()
        self.assertEqual(self.store.load(JOB)[0]["status"], "proposal_ready")

    def test_store_put_enforces_dev_and_expected_blob_sha(self):
        store = GitHubIncidentStore(threading.Lock())
        with patch("ai.incident_store.requests.put", return_value=Mock(status_code=409)) as put:
            with self.assertRaises(StorageConflict): store.save(JOB, self.queued(), "old-sha")
        self.assertEqual(put.call_args.kwargs["json"]["branch"], server.DEV_BRANCH)
        self.assertEqual(put.call_args.kwargs["json"]["sha"], "old-sha")
        with self.assertRaises(StorageError): store.url("../../main")


if __name__ == "__main__": unittest.main()
