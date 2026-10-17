# opencode-nix

Standalone Nix flake wrapping official prebuilt OpenCode CLI archives, with an optional Home Manager systemd user backend and a compaction-recovery skill.

## First run

The bootstrap version file intentionally has empty hashes. Run **Actions → Update OpenCode binaries → Run workflow**. The workflow downloads all upstream platform archives, hashes their actual bytes, and creates a release-update PR. Review and merge it before expecting the flake to build.

## Use

Add `inputs.opencode-nix.url = "github:p4p4j0hn/opencode-nix";` to your flake inputs.

Install CLI from `inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default`.

Import `inputs.opencode-nix.homeManagerModules.default` into Home Manager and enable `programs.opencode-nix.enable = true;`. See [the example](examples/home-manager.nix).

The optional backend runs `opencode serve` as a systemd user service with restart backoff. Bind to loopback by default. Use OpenCode's server password and a secured private endpoint for remote connectivity.

## Updating

The hourly GitHub workflow checks the latest stable upstream release and makes one pull request updating all four release hashes. It will not silently accept missing assets or mismatched upstream digests. Updates require review, and upstream CLI binaries are downloaded without a source build.

## Security and limitations

Do not give the backend unrestricted public access or put credentials in Nix store paths. The recovery skill instructs read-only access to OpenCode history and does not modify session databases. This initial revision supports one backend per user; richer multi-instance support, release signing verification and desktop builds can be added later.

License: MIT.
