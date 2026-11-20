{
  pkgs,
  home-manager,
  module,
}:
let
  makeHome =
    options:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        module
        (_: {
          home = {
            username = "ci";
            homeDirectory = "/home/ci";
            stateVersion = "26.11";
          };
          programs.opencode-nix = {
            enable = true;
            client.passwordFile = "/run/user/1000/opencode-password";
            backend = {
              enable = true;
              port = 4096;
              passwordCredential = "/run/user/1000/opencode-password";
              privateSocket.enable = true;
            };
            tui.theme = "system";
            context = "Test global context";
            commands.audit = "Audit the changes";
            agents.reviewer = "Review code";
            skills.sample = "Sample skill";
            themes.custom = {
              primary = "#123456";
            };
            tools.example = "export default {}";
            extraPackages = [ pkgs.git ];
            enableMcpIntegration = true;
            client.connections = {
              lab = {
                transport = "ssh";
                sshTarget = "builder.internal";
                localPort = 14096;
                passwordFile = "/run/user/1000/opencode-password";
              };
              unix = {
                transport = "ssh-unix";
                sshTarget = "builder.internal";
                remoteSocket = "/run/user/1000/opencode/opencode.sock";
                localPort = 15096;
              };
              direct = {
                transport = "direct";
                url = "https://code.internal";
              };
            };
          }
          // options;
        })
      ];
    }).config;
  server = makeHome { };
  client = makeHome { backend.enable = false; };
  takeoverServer = makeHome {
    backend = {
      enable = true;
      takeover.enable = true;
    };
  };
  aliasServer = makeHome {
    cli.tabs.mode = "auto";
    settings.model = "example/model";
    mutableSettings = true;
    validateFiles = {
      config = true;
      cli = true;
    };
  };
  backendLinuxAssertion = builtins.any (
    item:
    item.message == "OpenCode systemd backend requires Linux."
    && item.assertion == pkgs.stdenv.hostPlatform.isLinux
  ) server.assertions;
  service = server.systemd.user.services.opencode-backend.Service;
  tunnel = server.systemd.user.services.opencode-tunnel-lab.Service;
  unixTunnel = server.systemd.user.services.opencode-tunnel-unix.Service;
  privateBackend = server.systemd.user.services.opencode-backend.Service;
  backendScript = builtins.readFile (builtins.head privateBackend.ExecStart);
  tmpfilesOk = server.systemd.user.tmpfiles.rules == [ "d %t/opencode 0700 - - -" ];
  localClient = server.programs.opencode.package.passthru.opencodeClientScript;
  serviceOk =
    service.Restart == "always"
    && service.RestartSteps == 8
    && service.RestartMaxDelaySec == "5min"
    && builtins.match ".*pasta.*" (builtins.readFile (builtins.head service.ExecStart)) != null
    && service.LoadCredential == [ "opencode-password:/run/user/1000/opencode-password" ];
  tunnelOk =
    builtins.match ".*-L 127.0.0.1:14096:127.0.0.1:4096.*" (builtins.head tunnel.ExecStart) != null;
  unixTransportOk =
    builtins.match ".*-L %t/opencode/unix.sock:/run/user/1000/opencode/opencode.sock.*" (
      builtins.head unixTunnel.ExecStart
    ) != null;
  privateBackendOk =
    !(privateBackend ? PrivateNetwork)
    && builtins.match ".*pasta.*--config-net.*" backendScript != null
    && builtins.match ".*opencode-backend-private.*" backendScript != null
    && builtins.match ".*export OPENCODE_PASSWORD=.*" backendScript == null
    && !(server.systemd.user.services ? opencode-proxy);
  localRunner = builtins.readFile server.programs.opencode.package.passthru.opencodeLocalRunner;
  clientOk =
    pkgs.lib.hasInfix "--server" localRunner
    && pkgs.lib.hasInfix "http://127.0.0.1:4096" localRunner
    && pkgs.lib.hasInfix "PrivateNetwork=true" localClient
    && pkgs.lib.hasInfix "netns-runner" localClient
    && pkgs.lib.hasInfix "OPENCODE_PASSWORD" localClient
    && pkgs.lib.hasInfix "--setenv=OPENCODE_PASSWORD" localClient
    && pkgs.lib.hasInfix "opencode-password" localClient
    && pkgs.lib.hasInfix "refusing to start the standalone client" localClient;
  disabledOk = !(client.systemd.user.services ? opencode-backend);
  takeoverOk =
    builtins.length takeoverServer.systemd.user.services.opencode-backend.Service.ExecStartPre == 1
    &&
      builtins.match ".*takeover.*--port 4096.*" (
        builtins.head takeoverServer.systemd.user.services.opencode-backend.Service.ExecStartPre
      ) != null
    && server.systemd.user.services.opencode-backend.Service.ExecStartPre == [ ];
  commandsOk = builtins.length server.home.packages >= 3;
  upstreamAliasesOk =
    aliasServer.programs.opencode.cli.tabs.mode == "auto"
    && aliasServer.programs.opencode.mutableSettings
    && aliasServer.programs.opencode.validateFiles.cli
    && aliasServer.programs.opencode.validateFiles.config
    && builtins.hasAttr "opencode/home-manager-cli.json" aliasServer.xdg.configFile
    && builtins.hasAttr "opencode/home-manager.json" aliasServer.xdg.configFile
    && builtins.hasAttr "OPENCODE_CLI_CONFIG_CONTENT" aliasServer.home.sessionVariables
    && aliasServer.programs.opencode.package.passthru.jsonschema ? cli
    && aliasServer.programs.opencode.package.passthru.jsonschema ? config;
  upstreamOk =
    server.programs.opencode.enable
    && server.programs.opencode.tui.theme == "system"
    && server.programs.opencode.context == "Test global context"
    && server.programs.opencode.commands.audit == "Audit the changes"
    && server.programs.opencode.agents.reviewer == "Review code"
    && server.programs.opencode.skills.sample == "Sample skill"
    && builtins.hasAttr "compaction-recovery" server.programs.opencode.skills
    && server.programs.opencode.themes.custom.primary == "#123456"
    && server.programs.opencode.tools.example == "export default {}"
    && server.programs.opencode.enableMcpIntegration
    && builtins.length server.programs.opencode.extraPackages == 1;
in
assert backendLinuxAssertion;
assert serviceOk;
assert tunnelOk;
assert unixTransportOk;
assert privateBackendOk;
assert tmpfilesOk;
assert clientOk;
assert disabledOk;
assert takeoverOk;
assert commandsOk;
assert upstreamAliasesOk;
assert upstreamOk;
pkgs.writeText "opencode-home-manager-module-tested" "Home Manager remote client and systemd service evaluated successfully\n"
