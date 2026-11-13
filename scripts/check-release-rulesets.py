#!/usr/bin/env python3
"""Require an enforced main-branch GitHub ruleset before allowing auto-merge.

Reading repository rulesets uses the metadata-visible rulesets API, rather
than the legacy branch-protection API that rejects GitHub App tokens.
"""
import json
import os
import subprocess

REQUIRED_CHECKS = {"nix (ubuntu-26.04)", "nix (macos-latest)", "release-policy"}
REQUIRED_RULE_TYPES = {"pull_request", "non_fast_forward", "deletion"}


def gh_api(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def check_rulesets(summaries, detail):
    """Fail closed unless a single active main ruleset enforces all safeguards."""
    for summary in summaries:
        if (
            summary.get("target") != "branch"
            or summary.get("enforcement") != "active"
        ):
            continue
        ruleset = detail(summary["id"])
        conditions = ruleset.get("conditions", {}).get("ref_name", {})
        includes = conditions.get("include", [])
        excludes = conditions.get("exclude", [])
        if (
            ruleset.get("target") != "branch"
            or ruleset.get("enforcement") != "active"
            or not any(
                name in includes
                for name in ("refs/heads/main", "~DEFAULT_BRANCH", "~ALL")
            )
            or any(name in excludes for name in ("refs/heads/main", "~DEFAULT_BRANCH", "~ALL"))
            or ruleset.get("bypass_actors")
        ):
            continue

        rules = ruleset.get("rules", [])
        rule_types = {rule.get("type") for rule in rules}
        if not REQUIRED_RULE_TYPES.issubset(rule_types):
            continue
        for rule in rules:
            if rule.get("type") != "required_status_checks":
                continue
            params = rule.get("parameters", {})
            required = {
                item.get("context")
                for item in params.get("required_status_checks", [])
            }
            if (
                params.get("strict_required_status_checks_policy") is True
                and REQUIRED_CHECKS.issubset(required)
            ):
                print(
                    "Active main ruleset",
                    summary["id"],
                    "enforces:",
                    ", ".join(sorted(REQUIRED_CHECKS)),
                )
                return

    raise ValueError(
        "No active main ruleset enforces all required checks with strict "
        "up-to-date branches and no bypass actors; refusing auto-merge."
    )


def main():
    repo = os.environ["GH_REPO"]
    rulesets = gh_api(f"repos/{repo}/rulesets?per_page=100")
    if not isinstance(rulesets, list) or len(rulesets) == 100:
        raise ValueError("Could not exhaustively inspect repository rulesets.")
    check_rulesets(rulesets, lambda rid: gh_api(f"repos/{repo}/rulesets/{rid}"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as exc:
        raise SystemExit(str(exc)) from exc
