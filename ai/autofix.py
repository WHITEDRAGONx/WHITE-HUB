"""WHITE AI private auto-patch gate: no Lua execution, no main writes.

Only owner-authenticated jobs may reach this module; caller also requires
WHITEAI_AUTOPATCH_ENABLED=1. Parser checks are static, NOT Roblox tests.
"""
from __future__ import annotations

from tree_sitter import Language, Parser
import tree_sitter_luau

AUTO_PATCH_FILES = frozenset(("CombatFarm.lua", "Farm.lua", "UI.lua", "ServerHop.lua"))
SENSITIVE_TOKENS = (
    "GITHUB_TOKEN", "GEMINI_API_KEY", "WHITEAI_ADMIN_KEY",
    "WHITEAI_INGEST_KEY", "loadstring(", "getfenv(", "setfenv(",
)

def check_luau(source: str) -> bool:
    """Fail closed on an unavailable parser or syntax error."""
    try:
        parser = Parser(Language(tree_sitter_luau.language()))
        return not parser.parse(source.encode("utf-8")).root_node.has_error
    except Exception:
        return False

def checked_candidate(path: str, source: str, ai: dict) -> tuple[str | None, str]:
    if path not in AUTO_PATCH_FILES or ai.get("file") != path:
        return None, "file_not_auto_patchable"
    confidence = ai.get("confidence")
    if type(confidence) not in (int, float) or not 0.94 <= float(confidence) <= 1:
        return None, "confidence_too_low"
    old, new = ai.get("old_text"), ai.get("new_text")
    if not isinstance(old, str) or not isinstance(new, str):
        return None, "invalid_patch"
    if not old or old == new or len(old) > 2000 or len(new) > 2000:
        return None, "patch_out_of_bounds"
    if old.count("\n") > 35 or new.count("\n") > 35:
        return None, "patch_too_large"
    if source.count(old) != 1:
        return None, "source_match_not_unique"
    # Protect stable R15 XenonLock/Stand, item/merchant, and module exports.
    if path == "CombatFarm.lua":
        start = source.find("-- QUEST FARM")
        end = source.find("-- PUBLIC API", start)
        pos = source.find(old)
        if start < 0 or end < 0 or not start <= pos < end or pos + len(old) > end:
            return None, "combat_core_protected"
    if any(token.lower() in new.lower() and token.lower() not in old.lower()
           for token in SENSITIVE_TOKENS):
        return None, "forbidden_runtime_or_secret_api"
    candidate = source.replace(old, new, 1)
    if len(candidate) > 80_000:
        return None, "candidate_too_large"
    if path == "CombatFarm.lua":
        for name in ("Init", "StartNPC", "StartQuest", "Stop", "IsRunning"):
            signature = f"function CombatFarm:{name}("
            if signature not in candidate:
                return None, "export_contract_missing"
        # A patch inside the quest section must preserve the exact combat core.
        start = source.find("-- QUEST FARM")
        if candidate[:start] != source[:start]:
            return None, "combat_core_changed"
    if not check_luau(source):
        return None, "baseline_syntax_unverified"
    if not check_luau(candidate):
        return None, "candidate_syntax_error"
    return candidate, "static_syntax_passed"
