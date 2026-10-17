# Unattended upstream release merges

The updater downloads upstream binaries and opens a PR against `main`.
The `Release policy / release-policy` check verifies the bot branch only
modifies `version.json` and that its hashes match the official published
GitHub release asset digests. CI builds Linux/macOS before merging.

## Required repository settings

1. Create a **GitHub App** with repository permissions **Contents: Read and
   write**, **Pull requests: Read and write**, and **Metadata: Read**. Install
   it on `p4p4j0hn/opencode-nix`. Use a dedicated app, not the ChatGPT
   connector.
2. Set repository Actions variable `RELEASE_APP_ID` to its numeric App ID.
3. Set repository Actions secret `RELEASE_APP_PRIVATE_KEY` to its generated
   private key (PEM). Do not put the key in the repo.
4. In repository Settings > General > Pull Requests, enable **Allow auto-merge**.
5. Under Settings > Branches > Add branch protection rule for `main`:
   require a pull request and require these three status checks to pass:
   `nix (ubuntu-latest)`, `nix (macos-latest)`,
   `release-policy`. Require branches to be up to date before merging.
   Do not allow bypassing the rules. Do not require manual approvals if
   unattended merging is desired; normal code changes still need deliberate
   human review.
6. After verifying that each check runs on an App-created test PR, set Actions
   variable `RELEASE_AUTOMERGE_ENABLED` to `true`.

The release policy workflow will **not** arm auto-merge unless the opt-in
variable is true and branch protection currently requires all three checks.
GitHub then waits for required checks before merging.

If upstream lacks published SHA-256 asset digests, the release policy check
fails closed; review that release manually. A successful release-policy check
is not a substitute for source provenance verification or broader integration
testing. A protected-branch ruleset is essential because someone with rights
to modify workflow definitions can otherwise weaken CI.

## Verification

Use Actions > Update OpenCode binaries > Run workflow. If the latest version
is already on main, no PR is created. On the next release, verify the updater
PR is authored by the dedicated App, all three required checks run, and the
auto-merge option becomes armed. Never manually set the opt-in variable before
branch protection is configured.
