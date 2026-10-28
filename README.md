# opencode-nix

Standalone Nix flake wrapping official prebuilt OpenCode CLI archives, with an optional Home Manager systemd user backend and a compaction-recovery skill.

## Use

Add `inputs.opencode-nix.url = "github:p4p4j0hn/opencode-nix";` to your flake inputs.

Install CLI from `inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default`.

Import `inputs.opencode-nix.homeManagerModules.default` into Home Manager and enable `programs.opencode-nix.enable = true;`. See [the example](examples/home-manager.nix).

The optional backend runs `opencode serve` as a systemd user service with restart backoff. Bind to loopback by default. Use OpenCode's server password and a secured private endpoint for remote connectivity.

### Upstream Home Manager options

The wrapper forwards `programs.opencode-nix.cli`, `mutableSettings`, and `validateFiles` to their `programs.opencode` equivalents, alongside the existing aliases. The regular `programs.opencode` namespace remains available. This flake follows Home Manager `master` for OpenCode 2 option support; it does not support Home Manager releases missing these options.

```nix
programs.opencode-nix = {
  enable = true;
  cli.tabs.mode = "auto";
  mutableSettings = true;
};
```

For OpenCode 2, use `cli` rather than `tui`. `validateFiles` is an attribute set with `config`, `cli`, and `tui` flags, not a boolean. The prebuilt OpenCode 2 package includes pinned upstream `passthru.jsonschema.config` and `passthru.jsonschema.cli` values, so `validateFiles.config = true;` and `validateFiles.cli = true;` work without a package override. OpenCode 2 does not provide a `tui` schema; leave `validateFiles.tui = false;`. Schema hashes are updated with each upstream release and checked for upstream changes by the hourly updater.

## Updating

The hourly GitHub workflow checks the latest stable upstream release and makes one pull request updating all four release hashes. It will not silently accept missing assets or mismatched upstream digests. Updates require review, and upstream CLI binaries are downloaded without a source build.

## Security and limitations

Do not give the backend unrestricted public access or put credentials in Nix store paths. The recovery skill instructs read-only access to OpenCode history and does not modify session databases. This initial revision supports one backend per user; richer multi-instance support, release signing verification and desktop builds can be added later.

License: MIT.
