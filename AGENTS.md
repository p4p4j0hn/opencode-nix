# AGENTS.md

## Repository overview

This repository packages OpenCode and provides Home Manager and NixOS
integration for local and remote backends. The main implementation is in
`modules/home-manager.nix`; evaluation and runtime coverage is in `tests/`.

## Development environments

Both development shell entry points are supported:

```bash
nix develop
devenv shell
```

Use `devenv shell` when working with the Git hooks. It generates the local
`.pre-commit-config.yaml`, which is intentionally ignored.

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

- Keep secrets and runtime credentials out of the Nix store.
- Preserve backward compatibility unless a change explicitly requires a
  breaking option change.
- Add or update evaluation assertions when changing generated systemd units.
- Add or update NixOS integration coverage for runtime, namespace, socket, or
  networking behavior.
- Do not commit generated `.devenv/` or `.pre-commit-config.yaml` files.
- Do not commit or push on behalf of the user unless explicitly requested.

## Commit and pull request expectations

Use focused commits with an imperative subject. Pull requests should explain
the behavior change, mention affected options, and include the verification
commands that were run.
