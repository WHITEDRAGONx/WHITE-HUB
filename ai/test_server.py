"""No external requests or API keys are used by these tests."""
import unittest

from ai.server import clean_report, validate_proposal, proposal_markdown


class WhiteAITests(unittest.TestCase):
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
            "file": "CombatFarm.lua",
            "old_text": "local x = 1",
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
