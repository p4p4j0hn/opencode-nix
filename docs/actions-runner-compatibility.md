# GitHub Actions runner compatibility

The workflows use Node.js 24-compatible major versions:
- `actions/checkout@v6`
- `actions/create-github-app-token@v3`
- `peter-evans/create-pull-request@v8`

These majors require GitHub Actions Runner v2.327.1 or newer. GitHub-hosted
runners satisfy this requirement; self-hosted runners must be updated
before adopting these actions. The GitHub App token action continues to
accept the legacy `app-id` input in v3.

Ubuntu jobs are pinned to `ubuntu-24.04` instead of `ubuntu-latest`
to avoid an unreviewed upgrade to Ubuntu 26.04 during GitHub's staged
rollout in October and November 2026. The required branch-protection
check name remains `nix (ubuntu-latest)` for compatibility with
existing rules. This is a **legacy check name**, not a claim that the
job runs on the moving `ubuntu-latest` runner.

An independent `ubuntu-26.04-compat` CI job runs `nix flake check`
and the executable smoke test on 26.04. Initially, its failure does not
block merging; promote it to a required check and switch the main CI
runner after confirming consistent success.
