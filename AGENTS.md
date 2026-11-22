# AGENTS.md

## Repository overview

This repository packages OpenCode and provides Home Manager and NixOS
integration for local and remote backends. The main implementation is in
`modules/home-manager.nix`; evaluation and runtime coverage is in `tests/`.

## Development environments

Use `devenv shell` for normal development. It is the canonical environment
for contributors and agents because it installs and refreshes the repository's
Git hooks.

```bash
devenv shell
```

`nix develop` remains supported for compatibility and lightweight access to
the project's packages:

```bash
nix develop
```

The devenv environment generates the local `.pre-commit-config.yaml`, which is
intentionally ignored.

## Verification

Before submitting changes, run:

```bash
nix fmt -- --ci .
black --check --diff .
statix check .
nix flake check
devenv test
```

Changes to NixOS VM tests may require:

```bash
nix build .#vmTests.x86_64-linux.nixos-private-socket
```

## Change guidance

- Use test-driven development: add a failing test or evaluation assertion
  before implementing behavior, then make it pass and refactor.
- Keep secrets and runtime credentials out of the Nix store.
- Preserve backward compatibility unless a change explicitly requires a
  breaking option change.
- Add or update evaluation assertions when changing generated systemd units.
- Add or update NixOS integration coverage for runtime, namespace, socket, or
  networking behavior.
- Do not commit generated `.devenv/` or `.pre-commit-config.yaml` files.
- Do not commit or push on behalf of the user unless explicitly requested.

## Commit and pull request expectations

Commit early and often using focused snapshot commits with imperative
subjects. Intermediate commits do not need to be polished; pull requests may
be squash-merged at merge time. Pull requests should explain the behavior
change, mention affected options, and include the verification commands that
were run.
