# Contributing

## Getting started

Clone the repository and enter either supported development environment:

```bash
nix develop
```

or:

```bash
devenv shell
```

The devenv environment installs the repository's pre-commit hooks. The
generated `.pre-commit-config.yaml` is local-only and is ignored by Git.

## Local checks

Run the same formatting and lint checks used by CI:

```bash
nix fmt -- --ci .
black --check --diff .
statix check .
```

Run the full flake checks:

```bash
nix flake check
```

Or run the devenv task, which executes the configured hooks:

```bash
devenv test
```

## Making changes

1. Create a feature branch from `main`.
2. Keep changes focused and add tests for behavior changes.
3. Run the relevant checks locally.
4. Use a clear, imperative commit message.
5. Open a pull request against `main`.

For Home Manager or backend changes, update the evaluation assertions in
`tests/home-manager.nix`. For socket, namespace, or networking changes, also
update the appropriate NixOS test under `tests/`.

## Security and secrets

Do not commit API keys, private keys, passwords, credential files, or generated
runtime environment files. Use runtime paths and systemd credentials in test
fixtures and documentation.
