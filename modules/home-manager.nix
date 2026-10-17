self: { config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.programs.opencode-nix;
  opencodePkg = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
in {
  options.programs.opencode-nix = {
    enable = mkEnableOption "OpenCode from the opencode-nix flake";
    package = mkOption { type = types.package; default = opencodePkg; description = "OpenCode executable."; };
    settings = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = "OpenCode JSON configuration merged into ~/.config/opencode/opencode.json.";
    };
    backend = {
      enable = mkEnableOption "persistent OpenCode systemd user backend";
      host = mkOption { type = types.str; default = "127.0.0.1"; };
      port = mkOption { type = types.port; default = 4096; };
      environmentFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path containing OPENCODE_SERVER_PASSWORD and other secrets; never use a Nix store path.";
      };
    };
    recoverySkill.enable = mkOption { type = types.bool; default = true; };
  };
  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.configFile."opencode/opencode.json".text = builtins.toJSON ({ "$schema" = "https://opencode.ai/config.json"; } // cfg.settings);
    xdg.configFile."opencode/skills/compaction-recovery/SKILL.md" =
      mkIf cfg.recoverySkill.enable { source = ../skills/compaction-recovery/SKILL.md; };
    systemd.user.services.opencode-backend = mkIf cfg.backend.enable {
      Unit = {
        Description = "OpenCode persistent backend";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe cfg.package} serve --hostname ${lib.escapeShellArg cfg.backend.host} --port ${toString cfg.backend.port}";
        Restart = "always";
        RestartSec = "2s";
        RestartSteps = 8;
        RestartMaxDelaySec = "5min";
        EnvironmentFile = lib.optional (cfg.backend.environmentFile != null) cfg.backend.environmentFile;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
