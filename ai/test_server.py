"""Offline WHITE AI tests: no external requests, credentials, or billing used."""
import json
import os
import unittest
from unittest.mock import patch

from ai.server import (
    clean_report, validate_proposal, proposal_markdown,
    ask_ai, GeminiAPIError, gemini_error_classification, gemini_model,
    health,
)


class WhiteAITests(unittest.TestCase):
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
