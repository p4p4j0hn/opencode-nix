{ pkgs, home-manager, module }:
let
  makeHome = options: (home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      module
      ({ ... }: {
        home.username = "ci";
        home.homeDirectory = "/home/ci";
        home.stateVersion = "25.11";
        programs.opencode-nix = {
          enable = true;
          backend.enable = true;
          backend.port = 4096;
          tui.theme = "system";
          context = "Test global context";
          commands.audit = "Audit the changes";
          agents.reviewer = "Review code";
          skills.sample = "Sample skill";
          themes.custom = { primary = "#123456"; };
          tools.example = "export default {}";
          extraPackages = [ pkgs.git ];
          enableMcpIntegration = true;
          client.connections = {
            lab = {
              transport = "ssh";
              sshTarget = "builder.internal";
              localPort = 14096;
            };
            direct = {
              transport = "direct";
              url = "https://code.internal";
            };
          };
        } // options;
      })
    ];
  }).config;
  server = makeHome {};
  client = makeHome { backend.enable = false; };
  service = server.systemd.user.services.opencode-backend.Service;
  tunnel = server.systemd.user.services.opencode-tunnel-lab.Service;
  serviceOk =
    service.Restart == "always"
    && service.RestartSteps == 8
    && service.RestartMaxDelaySec == "5min"
    && builtins.match ".*serve.*" (builtins.head service.ExecStart) != null;
  tunnelOk =
    builtins.match ".*-L 127.0.0.1:14096:127.0.0.1:4096.*" (builtins.head tunnel.ExecStart) != null;
  disabledOk = !(client.systemd.user.services ? opencode-backend);
  commandsOk = builtins.length server.home.packages >= 3;
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
assert serviceOk;
assert tunnelOk;
assert disabledOk;
assert commandsOk;
assert upstreamOk;
pkgs.writeText "opencode-home-manager-module-tested" "Home Manager remote client and systemd service evaluated successfully\n"
