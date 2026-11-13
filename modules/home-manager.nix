self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.programs.opencode-nix;
  opencodePkg = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
  connections = cfg.client.connections;
  tunnelServiceName = name: "opencode-tunnel-${name}";
  backendServiceName = "opencode-backend.service";
  passwordSetup =
    passwordFile:
    lib.optionalString (passwordFile != null) ''
      password_file=${lib.escapeShellArg passwordFile}
      if [[ ! -r "$password_file" ]]; then
        echo "OpenCode password file is not readable: $password_file" >&2
        exit 1
      fi
      export OPENCODE_PASSWORD="$(${pkgs.coreutils}/bin/cat -- "$password_file")"
      if [[ -z "$OPENCODE_PASSWORD" ]]; then
        echo "OpenCode password file is empty: $password_file" >&2
        exit 1
      fi
    '';
  attachUrl =
    connection:
    if connection.transport == "ssh" then
      "http://127.0.0.1:${toString connection.localPort}"
    else
      connection.url;
  attachCommand =
    name: connection:
    pkgs.writeShellScriptBin "opencode-${name}" ''
      set -euo pipefail
      ${passwordSetup connection.passwordFile}
      ${lib.optionalString (connection.transport == "ssh") ''
        ${pkgs.systemd}/bin/systemctl --user start ${lib.escapeShellArg (tunnelServiceName name)}.service
        ready=0
        for i in $(${pkgs.coreutils}/bin/seq 1 50); do
          if (echo > /dev/tcp/127.0.0.1/${toString connection.localPort}) 2>/dev/null; then
            ready=1
            break
          fi
          ${pkgs.coreutils}/bin/sleep 0.2
        done
        if [[ "$ready" != 1 ]]; then
          echo "OpenCode SSH tunnel failed to become ready" >&2
          exit 1
        fi
      ''}
      exec ${lib.getExe cfg.package} --server ${lib.escapeShellArg (attachUrl connection)} "$@"
    '';
  localClientScript = ''
    set -euo pipefail
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet ${lib.escapeShellArg backendServiceName} 2>/dev/null; then
      ${passwordSetup cfg.client.passwordFile}
      exec ${lib.getExe cfg.package} --server ${lib.escapeShellArg "http://${cfg.backend.host}:${toString cfg.backend.port}"} "$@"
    fi
    exec ${lib.getExe cfg.package} "$@"
  '';
  localClientPackage =
    if !cfg.backend.enable then
      cfg.package
    else
      (pkgs.writeShellScriptBin "opencode" localClientScript).overrideAttrs (_: {
        pname = cfg.package.pname or "opencode";
        version = cfg.package.version or "0";
        meta = (cfg.package.meta or { }) // {
          mainProgram = "opencode";
        };
        passthru = (cfg.package.passthru or { }) // {
          opencodeClientScript = localClientScript;
        };
      });
in
{
  imports =
    map
      (name: lib.mkAliasOptionModule [ "programs" "opencode-nix" name ] [ "programs" "opencode" name ])
      [
        "extraPackages"
        "enableMcpIntegration"
        "tui"
        "web"
        "context"
        "commands"
        "agents"
        "skills"
        "themes"
        "tools"
      ];
  options.programs.opencode-nix = {
    enable = mkEnableOption "OpenCode from the opencode-nix flake";
    compatibility.homeManager26_05 = mkEnableOption "Home Manager 26.05 compatibility";
    cli = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };
    mutableSettings = mkOption {
      type = types.bool;
      default = false;
    };
    validateFiles = mkOption {
      type = types.attrsOf types.bool;
      default = { };
    };
    package = mkOption {
      type = types.package;
      default = opencodePkg;
      description = "OpenCode executable.";
    };
    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "OpenCode JSON configuration merged into ~/.config/opencode/opencode.json.";
    };
    backend = {
      enable = mkEnableOption "persistent OpenCode systemd user backend";
      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };
      port = mkOption {
        type = types.port;
        default = 4096;
      };
      takeover = {
        enable = mkEnableOption "take over the port from an existing same-user OpenCode serve process";
        graceSeconds = mkOption {
          type = types.ints.between 0 60;
          default = 5;
        };
      };
      environmentFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Runtime path containing OPENCODE_PASSWORD and other secrets; never use a Nix store path.";
      };
      passwordCredential = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path loaded as the backend's systemd password credential; use passwordFile separately for local clients.";
      };
    };
    client.passwordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Runtime path containing the OpenCode server password for the local client; never use a Nix store path.";
    };
    client.connections = mkOption {
      default = { };
      description = "Named remote OpenCode backends, exposed as opencode-<name> commands.";
      type = types.attrsOf (
        types.submodule (_: {
          options = {
            transport = mkOption {
              type = types.enum [
                "direct"
                "ssh"
              ];
              default = "ssh";
              description = "Direct HTTP (only on trusted networks) or an SSH local-port forward.";
            };
            url = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Complete HTTP(S) URL for direct transport.";
            };
            passwordFile = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Runtime path containing the server password; never use a Nix store path.";
            };
            sshTarget = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "OpenSSH host alias or user@host for SSH transport.";
            };
            remotePort = mkOption {
              type = types.port;
              default = 4096;
            };
            localPort = mkOption {
              type = types.port;
              default = 4096;
              description = "Local loopback listener for this SSH tunnel; unique per connection.";
            };
          };
        })
      );
    };
    recoverySkill.enable = mkOption {
      type = types.bool;
      default = true;
    };
  };
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.backend.enable || pkgs.stdenv.isLinux;
        message = "OpenCode systemd backend requires Linux.";
      }
      {
        assertion = !cfg.backend.takeover.enable || pkgs.stdenv.isLinux;
        message = "OpenCode takeover requires Linux.";
      }
    ]
    ++ lib.mapAttrsToList (name: connection: {
      assertion =
        builtins.match "[a-zA-Z0-9_-]+" name != null
        && (
          if connection.transport == "ssh" then
            connection.sshTarget != null && connection.url == null
          else
            connection.url != null && connection.sshTarget == null
        );
      message = "programs.opencode-nix.client.connections.${name}: use a safe name and set sshTarget (SSH) or url (direct), but not both.";
    }) connections
    ++ [
      {
        assertion =
          let
            ports = lib.mapAttrsToList (_: c: c.localPort) (
              lib.filterAttrs (_: c: c.transport == "ssh") connections
            );
          in
          builtins.length (lib.unique ports) == builtins.length ports;
        message = "OpenCode SSH connections must use distinct localPort values.";
      }
    ];
    programs.opencode = {
      enable = true;
      package = localClientPackage;
      inherit (cfg) settings;
      skills.compaction-recovery = mkIf cfg.recoverySkill.enable ../skills/compaction-recovery/SKILL.md;
    }
    // lib.optionalAttrs (!cfg.compatibility.homeManager26_05) {
      inherit (cfg) cli mutableSettings validateFiles;
    };
    home.packages = lib.mapAttrsToList attachCommand connections;
    systemd.user.services =
      lib.optionalAttrs cfg.backend.enable {
        opencode-backend = {
          Unit = {
            Description = "OpenCode persistent backend";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            ExecStart =
              if cfg.backend.passwordCredential == null then
                "${lib.getExe cfg.package} serve --hostname ${lib.escapeShellArg cfg.backend.host} --port ${toString cfg.backend.port}"
              else
                pkgs.writeShellScript "opencode-backend" ''
                  set -euo pipefail
                  export OPENCODE_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/opencode-password")"
                  exec ${lib.getExe cfg.package} serve --hostname ${lib.escapeShellArg cfg.backend.host} --port ${toString cfg.backend.port}
                '';
            ExecStartPre = lib.optional cfg.backend.takeover.enable "${pkgs.python3}/bin/python3 ${pkgs.writeText "opencode-takeover.py" (builtins.readFile ../scripts/takeover-port.py)} --port ${toString cfg.backend.port} --grace-seconds ${toString cfg.backend.takeover.graceSeconds}";
            Environment = lib.optional cfg.backend.takeover.enable "OPENCODE_LSOF=${pkgs.lsof}/bin/lsof";
            Restart = "always";
            RestartSec = "2s";
            RestartSteps = 8;
            RestartMaxDelaySec = "5min";
            EnvironmentFile = lib.optional (cfg.backend.environmentFile != null) cfg.backend.environmentFile;
            LoadCredential = lib.optional (
              cfg.backend.passwordCredential != null
            ) "opencode-password:${cfg.backend.passwordCredential}";
          };
          Install.WantedBy = [ "default.target" ];
        };
      }
      // (lib.mapAttrs' (
        name: connection:
        lib.nameValuePair (tunnelServiceName name) {
          Unit = {
            Description = "SSH tunnel to OpenCode backend (${name})";
            After = [ "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${pkgs.openssh}/bin/ssh -N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -L 127.0.0.1:${toString connection.localPort}:127.0.0.1:${toString connection.remotePort} ${lib.escapeShellArg connection.sshTarget}";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        }
      ) (lib.filterAttrs (_: c: c.transport == "ssh") connections));
  };
}
