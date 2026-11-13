"""Unit tests for safe ruleset-based release auto-merge gate."""

import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / "scripts" / "check-release-rulesets.py"
spec = importlib.util.spec_from_file_location("check_release_rulesets", path)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def ruleset(rules=None, *, enforced="active", include=None, exclude=None, bypass=None):
    if rules is None:
        rules = [
            {
                "type": "required_status_checks",
                "parameters": {
                    "strict_required_status_checks_policy": True,
                    "required_status_checks": [
                        {"context": context}
                        for context in sorted(policy.REQUIRED_CHECKS)
                    ],
                },
            },
            {"type": "pull_request"},
            {"type": "non_fast_forward"},
            {"type": "deletion"},
        ]
    return {
        "target": "branch",
        "enforcement": enforced,
        "conditions": {
            "ref_name": {
                "include": ["refs/heads/main"] if include is None else include,
                "exclude": [] if exclude is None else exclude,
            }
        },
        "rules": rules,
        "bypass_actors": [] if bypass is None else bypass,
    }


class RuleSetTests(unittest.TestCase):
    def test_valid_required_checks_allow_merging(self):
        policy.check_rulesets(
            [{"id": 22, "target": "branch", "enforcement": "active"}],
            lambda _: ruleset(),
        )

    def test_missing_check_fails_closed(self):
        data = ruleset()
        checks = data["rules"][0]["parameters"]["required_status_checks"]
        checks.pop()
        with self.assertRaisesRegex(ValueError, "required checks"):
            policy.check_rulesets(
                [{"id": 22, "target": "branch", "enforcement": "active"}],
                lambda _: data,
            )

    def test_non_strict_checks_fail_closed(self):
        data = ruleset()
        data["rules"][0]["parameters"]["strict_required_status_checks_policy"] = False
        with self.assertRaisesRegex(ValueError, "required checks"):
            policy.check_rulesets(
                [{"id": 22, "target": "branch", "enforcement": "active"}],
                lambda _: data,
            )

    def test_other_branch_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "required checks"):
            policy.check_rulesets(
                [{"id": 22, "target": "branch", "enforcement": "active"}],
                lambda _: ruleset(include=["refs/heads/staging"]),
            )

    def test_bypass_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "required checks"):
            policy.check_rulesets(
                [{"id": 22, "target": "branch", "enforcement": "active"}],
                lambda _: ruleset(bypass=[{"actor_id": 123, "actor_type": "Integration"}]),
            )

    def test_nonfastforward_guard_must_exist(self):
        data = ruleset()
        data["rules"] = [rule for rule in data["rules"] if rule["type"] != "non_fast_forward"]
        with self.assertRaisesRegex(ValueError, "required checks"):
            policy.check_rulesets(
                [{"id": 22, "target": "branch", "enforcement": "active"}],
                lambda _: data,
            )


if __name__ == "__main__":
    unittest.main()
