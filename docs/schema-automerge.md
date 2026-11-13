# Automated schema updates

The scheduled updater stages all generated files beneath `schemas/`, along
with `version.json` and any changed `flake.lock`. It does not impose a
four-file cap. A schema-only update does not need a changed `flake.lock`.

The release-policy gate validates each registered schema against its pinned
SHA-256, JSON schema identity and expected structure; it also validates all
platform binary pins against the npm integrity hashes. Only files in the
curated schema registry (`SCHEMAS` in `scripts/verify-release-pr.py`) are
eligible for unattended merging. Register a new schema generator and trusted
source through a reviewed code change before allowing it into unattended
updates. Unregistered schema JSON, code, policy modifications or deleted
schema files cannot be auto-merged.

Auto-merge additionally requires an active GitHub **main ruleset** enforcing
`release-policy`, `nix (ubuntu-26.04)`, and `nix (macos-latest)`, strict
up-to-date checks, pull requests, force-push and deletion protections, with
no bypass actors. The guard uses the public rulesets API rather than the
legacy branch-protection API, which returned HTTP 403 for the GitHub App.

GitHub remains responsible for waiting until required checks pass. All
other release PRs must receive normal manual review.
