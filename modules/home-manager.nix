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
  netnsRunner =
    {
      label,
      port,
      socketName,
    }:
    pkgs.writeShellScript "opencode-${label}-netns-runner" ''
      set -euo pipefail
      socket_path="''${XDG_RUNTIME_DIR:-/run/user/$UID}/opencode/${socketName}"
      ${pkgs.socat}/bin/socat TCP-LISTEN:${toString port},bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:"$socket_path" &
      proxy_pid=$!
      trap 'kill "$proxy_pid" 2>/dev/null || true' EXIT
      ready=0
      for i in $(${pkgs.coreutils}/bin/seq 1 50); do
        if ! kill -0 "$proxy_pid" 2>/dev/null; then
          echo "OpenCode private socket proxy failed to start" >&2
          exit 1
        fi
        if (echo > /dev/tcp/127.0.0.1/${toString port}) 2>/dev/null; then
          ready=1
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      if [[ "$ready" != 1 ]]; then
        echo "OpenCode private socket proxy failed to become ready" >&2
        exit 1
      fi
      ${lib.getExe cfg.package} --server "http://127.0.0.1:${toString port}" "$@"
    '';
  attachUrl =
    connection:
    if connection.transport == "ssh" || connection.transport == "ssh-unix" then
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
      ${lib.optionalString (connection.transport == "ssh-unix") ''
        ${pkgs.systemd}/bin/systemctl --user start ${lib.escapeShellArg (tunnelServiceName name)}.service
        ${pkgs.coreutils}/bin/sleep 0.2
        ready=0
        for i in $(${pkgs.coreutils}/bin/seq 1 50); do
          if [[ -S "$XDG_RUNTIME_DIR/opencode/${name}.sock" ]]; then ready=1; break; fi
          ${pkgs.coreutils}/bin/sleep 0.2
        done
        if [[ "$ready" != 1 ]]; then
          echo "OpenCode SSH Unix-socket tunnel failed to become ready" >&2
          exit 1
        fi
      ''}
      ${
        if connection.transport == "ssh-unix" then
          "exec ${pkgs.systemd}/bin/systemd-run --user --wait --collect --quiet --pty --working-directory \"\$PWD\" -p PrivateNetwork=true ${
            lib.optionalString (connection.passwordFile != null) "--setenv=OPENCODE_PASSWORD "
          }-- ${
            netnsRunner {
              label = name;
              port = connection.localPort;
              socketName = "${name}.sock";
            }
          } \"$@\""
        else
          "exec ${lib.getExe cfg.package} --server ${lib.escapeShellArg (attachUrl connection)} \"$@\""
      }
    '';
  localRunner = netnsRunner {
    label = "local";
    port = cfg.backend.port;
    socketName = "opencode.sock";
  };
  backendServeCommand = "${lib.getExe cfg.package} serve --hostname ${
    lib.escapeShellArg (if cfg.backend.privateSocket.enable then "127.0.0.1" else cfg.backend.host)
  } --port ${toString cfg.backend.port}";
  backendCredentialExport = "export OPENCODE_SERVER_PASSWORD=\"$(cat \"$CREDENTIALS_DIRECTORY/opencode-password\")\"";
  privateBackendScript = pkgs.writeShellScript "opencode-backend-private" ''
    set -euo pipefail
    ${lib.optionalString (cfg.backend.passwordCredential != null) backendCredentialExport}
    socket_path="$XDG_RUNTIME_DIR/opencode/opencode.sock"
    ${pkgs.coreutils}/bin/rm -f "$socket_path"
    ${pkgs.socat}/bin/socat UNIX-LISTEN:"$socket_path",mode=0600,fork TCP:127.0.0.1:${toString cfg.backend.port} &
    exec ${backendServeCommand}
  '';
  backendExecStart =
    if cfg.backend.privateSocket.enable then
      pkgs.writeShellScript "opencode-backend" ''
        set -euo pipefail
        exec ${lib.getExe' pkgs.passt "pasta"} --config-net --foreground --quiet --tcp-ports none --udp-ports none --map-host-loopback 192.168.1.2 -- ${privateBackendScript} "$@"
      ''
    else if cfg.backend.passwordCredential == null then
      backendServeCommand
    else
      pkgs.writeShellScript "opencode-backend" ''
        set -euo pipefail
        ${backendCredentialExport}
        exec ${backendServeCommand}
      '';
  localClientScript = ''
    set -euo pipefail
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet ${lib.escapeShellArg backendServiceName} 2>/dev/null; then
       ${passwordSetup cfg.client.passwordFile}
       ${
         if cfg.backend.privateSocket.enable then
            "exec ${pkgs.systemd}/bin/systemd-run --user --wait --collect --quiet --pty --working-directory \"\$PWD\" -p PrivateNetwork=true ${
             lib.optionalString (cfg.client.passwordFile != null) "--setenv=OPENCODE_PASSWORD "
           }-- ${localRunner} \"$@\""
         else
           "exec ${lib.getExe cfg.package} --server ${lib.escapeShellArg "http://${cfg.backend.host}:${toString cfg.backend.port}"} \"$@\""
       }
    fi
    echo "OpenCode backend service is not active; refusing to start the standalone client." >&2
    echo "Check: systemctl --user status ${backendServiceName}" >&2
    exit 1
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
          opencodeLocalRunner = localRunner;
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
      privateSocket.enable = mkEnableOption "private Unix-socket backend transport";
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
                "ssh-unix"
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
            remoteSocket = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Remote Unix socket path for ssh-unix transport.";
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
        assertion = !cfg.backend.enable || pkgs.stdenv.hostPlatform.isLinux;
        message = "OpenCode systemd backend requires Linux.";
      }
      {
        assertion = !cfg.backend.takeover.enable || pkgs.stdenv.hostPlatform.isLinux;
        message = "OpenCode takeover requires Linux.";
      }
    ]
    ++ lib.mapAttrsToList (name: connection: {
      assertion =
        builtins.match "[a-zA-Z0-9_-]+" name != null
        && (
          if connection.transport == "ssh" then
            connection.sshTarget != null && connection.url == null && connection.remoteSocket == null
          else if connection.transport == "ssh-unix" then
            connection.sshTarget != null && connection.remoteSocket != null && connection.url == null
          else
            connection.url != null && connection.sshTarget == null && connection.remoteSocket == null
        );
      message = "programs.opencode-nix.client.connections.${name}: use a safe name and set sshTarget (SSH) or url (direct), but not both.";
    }) connections
    ++ [
      {
        assertion =
          let
            ports = lib.mapAttrsToList (_: c: c.localPort) (
              lib.filterAttrs (_: c: c.transport == "ssh" || c.transport == "ssh-unix") connections
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
    systemd.user = {
      services =
        lib.optionalAttrs cfg.backend.enable {
          opencode-backend = {
            Unit = {
              Description = "OpenCode persistent backend";
              After = [ "network-online.target" ];
              Wants = [ "network-online.target" ];
            };
            Service = {
              ExecStart = backendExecStart;
              ExecStartPre = lib.optional cfg.backend.takeover.enable "${pkgs.python3}/bin/python3 ${pkgs.writeText "opencode-takeover.py" (builtins.readFile ../scripts/takeover-port.py)} --port ${toString cfg.backend.port} --grace-seconds ${toString cfg.backend.takeover.graceSeconds}";
              Environment = lib.optional cfg.backend.takeover.enable "OPENCODE_LSOF=${pkgs.lsof}/bin/lsof";
              Restart = "always";
              RestartSec = "2s";
              RuntimeDirectory = lib.optional cfg.backend.privateSocket.enable "opencode";
              RuntimeDirectoryMode = lib.optional cfg.backend.privateSocket.enable "0700";
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
        ) (lib.filterAttrs (_: c: c.transport == "ssh") connections))
        // (lib.mapAttrs' (
          name: connection:
          lib.nameValuePair (tunnelServiceName name) {
            Unit.Description = "SSH Unix socket tunnel to OpenCode backend (${name})";
            Service = {
              Type = "simple";
              RuntimeDirectory = "opencode";
              RuntimeDirectoryMode = "0700";
              ExecStart = "${pkgs.openssh}/bin/ssh -N -T -o BatchMode=yes -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L %t/opencode/${name}.sock:${connection.remoteSocket} ${lib.escapeShellArg connection.sshTarget}";
              Restart = "on-failure";
              RestartSec = "5s";
            };
          }
        ) (lib.filterAttrs (_: c: c.transport == "ssh-unix") connections));
      tmpfiles.rules = lib.optional (
        cfg.backend.privateSocket.enable
        || lib.any (c: c.transport == "ssh-unix") (lib.attrValues connections)
      ) "d %t/opencode 0700 - - -";
    };
  };
}
