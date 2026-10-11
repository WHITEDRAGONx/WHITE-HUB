"""Offline WHITE AI tests: no external requests, credentials, or billing used."""
import json
import os
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from ai.server import (
    clean_report, validate_proposal, proposal_markdown,
    ask_ai, GeminiAPIError, gemini_error_classification, gemini_model,
    health, report_needs_ai, run_job, _jobs,
    owner_autopatch_enabled, attempt_dev_commit,
)

from ai.autofix import checked_candidate, check_luau

class WhiteAITests(unittest.TestCase):
    def test_active_dev_luau_files_parse_without_syntax_errors(self):
        project = Path(__file__).resolve().parents[1]
        for module in ("CombatFarm.lua", "WhiteAI.lua", "UI.lua"):
            with self.subTest(module=module):
                self.assertTrue(check_luau((project / module).read_text(encoding="utf-8")),
                                f"{module} has syntax errors or unrecognized grammar")

    def test_private_admin_requires_separate_secret_and_explicit_enable(self):
        request = SimpleNamespace(headers={"X-WhiteAI-Admin-Key": "x" * 40})
        with patch.dict(os.environ, {"WHITEAI_ADMIN_KEY": "x" * 40,
                                     "WHITEAI_AUTOPATCH_ENABLED": "0"}):
            self.assertFalse(owner_autopatch_enabled(request))
        with patch.dict(os.environ, {"WHITEAI_ADMIN_KEY": "x" * 40,
                                     "WHITEAI_AUTOPATCH_ENABLED": "1"}):
            self.assertTrue(owner_autopatch_enabled(request))
            self.assertFalse(owner_autopatch_enabled(SimpleNamespace(headers={})))
            with self.assertRaises(Exception):
                owner_autopatch_enabled(SimpleNamespace(
                    headers={"X-WhiteAI-Admin-Key": "wrong"}))
        with patch.dict(os.environ, {"WHITEAI_ADMIN_KEY": "",
                                     "WHITEAI_AUTOPATCH_ENABLED": "1"}):
            with self.assertRaises(Exception):
                owner_autopatch_enabled(request)

    def test_luau_syntax_gate_rejects_invalid_code(self):
        self.assertTrue(check_luau("local x = 1\nreturn x\n"))
        self.assertFalse(check_luau("local x ="))

    def test_private_patch_requires_high_confidence_and_exact_match(self):
        base = "local enabled = true\nreturn enabled\n"
        ai = {"file": "Farm.lua", "confidence": 0.99,
              "old_text": "true", "new_text": "false"}
        code, reason = checked_candidate("Farm.lua", base, ai)
        self.assertEqual(reason, "static_syntax_passed")
        self.assertIn("enabled = false", code)
        ai["confidence"] = 0.79
        self.assertIsNone(checked_candidate("Farm.lua", base, ai)[0])
        ai["confidence"] = 0.99
        ai["old_text"] = "not-an-exact-substring"
        self.assertIsNone(checked_candidate("Farm.lua", base, ai)[0])

    def test_inventory_and_protected_core_never_auto_patch(self):
        src = "local x = true\nreturn x\n"
        ai = {"file": "Inventory.lua", "confidence": 1,
              "old_text": "true", "new_text": "false"}
        self.assertIsNone(checked_candidate("Inventory.lua", src, ai)[0])
        src = ("function CombatFarm:StartQuest() end\n"
               "-- QUEST FARM\nlocal active = true\n"
               "-- PUBLIC API\nfunction CombatFarm:StartNPC() end\n")
        ai.update(file="CombatFarm.lua", old_text="function CombatFarm:StartQuest() end",
                  new_text="function CombatFarm:StartQuest() return true end")
        self.assertEqual(checked_candidate("CombatFarm.lua", src, ai)[1],
                         "combat_core_protected")

    def test_autopatch_requires_fresh_source_no_write_on_conflict(self):
        with patch("ai.server.checked_candidate",
                   return_value=("local x = 2", "static_syntax_passed")):
            with patch("ai.server.read_github_file", return_value=("different", "new-sha")):
                with patch("ai.server.requests.put") as write:
                    result = attempt_dev_commit("a" * 20, "Farm.lua",
                                                "local x = 1", "old-sha",
                                                {"file": "Farm.lua", "confidence": 0.99})
        self.assertEqual(result["reason"], "stale_source")
        write.assert_not_called()

    def test_backup_record_precedes_any_dev_source_commit(self):
        class MockReply:
            def __init__(self, obj):
                self.obj = obj
            def raise_for_status(self):
                return None
            def json(self):
                return self.obj
        replies = [MockReply({}), MockReply({"commit": {"sha": "new-dev-commit"}})]
        with patch.dict(os.environ, {"GITHUB_TOKEN": "dummy-test-only"}):
            with patch("ai.server.checked_candidate",
                       return_value=("local x = 2", "static_syntax_passed")):
                with patch("ai.server.read_github_file",
                           return_value=("local x = 1", "original-blob")):
                    with patch("ai.server.requests.get",
                               return_value=MockReply({"commit": {"sha": "pre-patch-commit"}})):
                        with patch("ai.server.requests.put", side_effect=replies) as writes:
                            result = attempt_dev_commit("a" * 20, "Farm.lua",
                                                        "local x = 1", "original-blob",
                                                        {"file": "Farm.lua"})
        self.assertEqual(result["state"], "dev_committed_unverified")
        self.assertEqual(writes.call_count, 2)
        backup = writes.call_args_list[0]
        changed = writes.call_args_list[1]
        self.assertIn("/contents/ai/backups/", backup.args[0])
        self.assertIn("/contents/Farm.lua", changed.args[0])
        self.assertEqual(changed.kwargs["json"]["sha"], "original-blob")
        self.assertEqual(backup.kwargs["json"]["branch"], "dev/2026-10-10-autosell-compat")
        self.assertEqual(changed.kwargs["json"]["branch"], "dev/2026-10-10-autosell-compat")

    def test_gemini_429_safe_classification(self):
        code, hint = gemini_error_classification(429)
        self.assertEqual(code, "gemini_rate_limited")
        self.assertIn("quota", hint.lower())

    def test_gemini_auth_and_model_errors(self):
        self.assertEqual(gemini_error_classification(403)[0], "gemini_auth_error")
        self.assertEqual(gemini_error_classification(404)[0], "gemini_model_unavailable")

    def test_gemini_uses_header_and_structured_json(self):
        class FakeResponse:
            status_code = 200
            def json(self):
                return {"candidates": [{"content": {"parts": [{
                    "text": json.dumps({
                        "summary": "test", "hypothesis": "none", "confidence": 0.1,
                        "file": "Farm.lua", "old_text": "", "new_text": "",
                        "tests": ["Review logs"],
                    })
                }]}}]}
        with patch.dict(os.environ, {"GEMINI_API_KEY": "fake-test-key", "GEMINI_MODEL": "gemini-3.8-flash"}):
            with patch("ai.server.requests.post", return_value=FakeResponse()) as send:
                result = ask_ai({"reason": "test"}, "Farm.lua", "local test = 1")
        self.assertEqual(result["file"], "Farm.lua")
        args, kwargs = send.call_args
        self.assertEqual(args[0], "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        self.assertEqual(kwargs["headers"]["x-goog-api-key"], "fake-test-key")
        self.assertFalse(kwargs["allow_redirects"])
        self.assertEqual(kwargs["json"]["generationConfig"]["responseMimeType"], "application/json")
        self.assertNotIn("fake-test-key", json.dumps(kwargs["json"]))

    def test_gemini_http_error_never_echoes_provider_message(self):
        class FakeResponse:
            status_code = 429
            text = "raw-provider-private-token"
        with patch.dict(os.environ, {"GEMINI_API_KEY": "fake-test-key"}):
            with patch("ai.server.requests.post", return_value=FakeResponse()):
                with self.assertRaises(GeminiAPIError) as error:
                    ask_ai({"reason": "test"}, "Farm.lua", "return true")
        self.assertEqual(error.exception.code, "gemini_rate_limited")
        self.assertNotIn("raw-provider-private-token", str(error.exception))

    def test_503_retries_primary_once_then_uses_free_lite(self):
        class Failure:
            status_code = 503
            text = "do not show provider response"
        class Success:
            status_code = 200
            def json(self):
                return {"candidates": [{"content": {"parts": [{
                    "text": json.dumps({
                        "summary": "Need logs", "hypothesis": "Unknown",
                        "confidence": 0.2, "file": "Farm.lua",
                        "old_text": "", "new_text": "", "tests": ["Verify in game"],
                    })
                }]}}]}
        with patch.dict(os.environ, {"GEMINI_API_KEY": "fake-test-key",
                                     "GEMINI_MODEL": "gemini-3.8-flash"}):
            with patch("ai.server.requests.post",
                       side_effect=[Failure(), Failure(), Success()]) as send:
                with patch("ai.server.time.sleep") as pause:
                    result = ask_ai({"reason": "test"}, "Farm.lua", "return true")
        self.assertEqual(result["file"], "Farm.lua")
        self.assertEqual(send.call_count, 3)
        self.assertIn("gemini-3.8-flash:generateContent", send.call_args_list[0].args[0])
        self.assertIn("gemini-3.8-flash:generateContent", send.call_args_list[1].args[0])
        self.assertIn("gemini-3.5-flash-lite:generateContent", send.call_args_list[2].args[0])
        pause.assert_called_once_with(1.5)

    def test_429_and_403_never_retry_or_fallback(self):
        for http_status, expected in ((429, "gemini_rate_limited"),
                                      (403, "gemini_auth_error")):
            class Failure:
                status_code = http_status
                text = "private provider response"
            with patch.dict(os.environ, {"GEMINI_API_KEY": "fake-test-key",
                                         "GEMINI_MODEL": "gemini-3.8-flash"}):
                with patch("ai.server.requests.post", return_value=Failure()) as send:
                    with patch("ai.server.time.sleep") as pause:
                        with self.assertRaises(GeminiAPIError) as error:
                            ask_ai({"reason": "test"}, "Farm.lua", "return true")
            self.assertEqual(error.exception.code, expected)
            self.assertEqual(send.call_count, 1)
            pause.assert_not_called()

    def test_5xx_fallback_is_bounded_when_both_models_down(self):
        class Failure:
            status_code = 503
            text = "private response"
        with patch.dict(os.environ, {"GEMINI_API_KEY": "fake-test-key",
                                     "GEMINI_MODEL": "gemini-3.8-flash"}):
            with patch("ai.server.requests.post", return_value=Failure()) as send:
                with patch("ai.server.time.sleep"):
                    with self.assertRaises(GeminiAPIError) as error:
                        ask_ai({"reason": "test"}, "Farm.lua", "return true")
        self.assertEqual(error.exception.code, "gemini_unavailable")
        self.assertEqual(send.call_count, 3)
        self.assertNotIn("private response", str(error.exception))

    def test_default_model_and_disallow_external_model_url(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(gemini_model(), "gemini-3.8-flash")
        with patch.dict(os.environ, {"GEMINI_MODEL": "https://malicious.example"}):
            with self.assertRaises(ValueError):
                gemini_model()

    def test_health_uses_gemini_settings_only(self):
        with patch.dict(os.environ, {"GITHUB_TOKEN": "test", "GEMINI_API_KEY": "test",
                                     "OPENAI_API_KEY": ""}, clear=True):
            self.assertTrue(health()["configured"])
        with patch.dict(os.environ, {"GITHUB_TOKEN": "test", "OPENAI_API_KEY": "legacy"},
                        clear=True):
            self.assertFalse(health()["configured"])

    def test_empty_manual_report_skips_gemini_quota(self):
        empty = clean_report({
            "category": "manual_diagnostic", "module": "General",
            "reason": "Manual review requested",
            "context": {"recent": [{"module": "Farm", "level": "INFO",
                                    "message": "Loop started"}]},
        })
        self.assertFalse(report_needs_ai(empty))
        empty["context"]["quest_enabled"] = True
        self.assertTrue(report_needs_ai(empty))
        empty["context"]["quest_enabled"] = False
        empty["context"]["recent"][0]["level"] = "WARN"
        self.assertTrue(report_needs_ai(empty))

    def test_explicit_quest_incident_always_analyzed(self):
        report = clean_report({
            "category": "quest_stall", "module": "CombatFarm",
            "reason": "Quest progress unchanged",
        })
        self.assertTrue(report_needs_ai(report))

    def test_sanitized_job_result_has_review_url_and_summary(self):
        job = "offline-mocked-job"
        _jobs[job] = {"status": "queued"}
        report = clean_report({
            "category": "quest_stall", "module": "CombatFarm",
            "reason": "No progress",
        })
        proposed = {
            "summary": "Needs logs about quest",
            "hypothesis": "Dialogue not confirmed",
            "confidence": 0.25, "file": "CombatFarm.lua",
            "old_text": "", "new_text": "", "tests": [],
        }
        try:
            with patch("ai.server.read_github_file", return_value=("local x = 1", "abc123")):
                with patch("ai.server.ask_ai", return_value=proposed):
                    with patch("ai.server.publish_review_artifact",
                               return_value="https://github.com/WHITEDRAGONx/WHITE-HUB-V3/") as save:
                        run_job(job, report)
            self.assertEqual(_jobs[job]["status"], "proposal_ready")
            self.assertEqual(_jobs[job]["confidence"], 0.25)
            self.assertEqual(_jobs[job]["module"], "CombatFarm.lua")
            self.assertIn("Needs logs", _jobs[job]["diagnosis"])
            save.assert_called_once()
        finally:
            _jobs.pop(job, None)

    def test_rejects_arbitrary_paths(self):
        self.assertEqual(validate_proposal({
            "file": "Inventory.lua", "old_text": "a", "new_text": "b"
        }, "Inventory.lua", "a"), "")

    def test_must_match_exactly_once(self):
        self.assertEqual(validate_proposal({
            "file": "CombatFarm.lua", "old_text": "foo", "new_text": "bar"
        }, "CombatFarm.lua", "foo\nfoo\n"), "")

    def test_valid_review_diff(self):
        source = "local x = 1\nreturn x\n"
        result = validate_proposal({
            "file": "CombatFarm.lua", "old_text": "local x = 1",
            "new_text": "local x = 2",
        }, "CombatFarm.lua", source)
        self.assertIn("-local x = 1", result)
        self.assertIn("+local x = 2", result)

    def test_report_sanitizes_urls(self):
        result = clean_report({
            "module": "CombatFarm",
            "reason": "error https://discord.com/api/webhooks/123/SECRET",
            "context": {"recent": [{"level": "WARN", "module": "CombatFarm",
                                    "message": "bad https://private.example/path"}]}
        })
        self.assertNotIn("SECRET", result["reason"])
        self.assertEqual(result["context"]["recent"][0]["message"], "bad [URL]")

    def test_diagnostic_only_proposal(self):
        text = proposal_markdown({
            "category": "quest_stall", "reason": "no progress"
        }, "CombatFarm.lua", "abc123", {
            "summary": "Insufficient data", "hypothesis": "Unknown",
            "confidence": 0.3, "tests": ["Capture dialogue state"],
        }, "")
        self.assertIn("NOT APPLIED", text)
        self.assertIn("No validated patch produced", text)


if __name__ == "__main__":
    unittest.main()
