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
    && builtins.match ".*serve.*" service.ExecStart != null;
  tunnelOk =
    builtins.match ".*-L 127.0.0.1:14096:127.0.0.1:4096.*" tunnel.ExecStart != null;
  disabledOk = !(client.systemd.user.services ? opencode-backend);
  commandsOk = builtins.length server.home.packages == 3;
in
assert serviceOk;
assert tunnelOk;
assert disabledOk;
assert commandsOk;
pkgs.writeText "opencode-home-manager-module-tested" "Home Manager remote client and systemd service evaluated successfully\n"
