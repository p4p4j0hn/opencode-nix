{
  pkgs,
  self,
  home-manager,
}:
pkgs.testers.nixosTest {
  name = "opencode-private-socket-runtime";

  nodes = {
    server =
      { config, ... }:
      {
        imports = [ home-manager.nixosModules.home-manager ];
        networking.firewall.enable = false;
        environment.systemPackages = [
          pkgs.curl
          pkgs.openssh
          pkgs.sshpass
          pkgs.socat
        ];
        systemd.tmpfiles.rules = [ "d /run/opencode 0700 ci users -" ];
        users.users.ci = {
          isNormalUser = true;
          password = "ci";
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPDF/GeX8zCFYeTC6/CGYcRRyv/KmuqSngfoNB3F0wnW john@defiant"
          ];
        };
        environment.etc."ci-key" = {
          mode = "0600";
          user = "ci";
          text = ''
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
            QyNTUxOQAAACDwxfxnl/MwhWHkwuvwhmHEUcr/yprqkp4H6DQdxdMJ1gAAAJC0Ls9PtC7P
            TwAAAAtzc2gtZWQyNTUxOQAAACDwxfxnl/MwhWHkwuvwhmHEUcr/yprqkp4H6DQdxdMJ1g
            AAAEDN+Kh/p+VXuP+aiXHV5/iGTlB9gBmHKTy7ox6kUXQv6vDF/GeX8zCFYeTC6/CGYcRR
            yv/KmuqSngfoNB3F0wnWAAAADGpvaG5AZGVmaWFudAE=
            -----END OPENSSH PRIVATE KEY-----
          '';
        };
        environment.etc."opencode-password".text = "secret\n";
        services.openssh.enable = true;
        services.openssh.settings = {
          PasswordAuthentication = true;
          AllowStreamLocalForwarding = "yes";
        };
        home-manager.users.ci = {
          imports = [ self.homeManagerModules.default ];
          home.stateVersion = "25.11";
          programs.opencode-nix = {
            enable = true;
            backend.enable = false;
            package = pkgs.writeShellScriptBin "opencode-fixture-client" ''
              set -euo pipefail
              if [[ "$1" != "--server" ]]; then exit 2; fi
              ${pkgs.curl}/bin/curl -fsS -u opencode:secret "$2"
            '';
            client.connections.fixture = {
              transport = "ssh-unix";
              sshTarget = "ci@localhost";
              remoteSocket = "/run/opencode/opencode.sock";
              localPort = 15096;
              passwordFile = "/etc/opencode-password";
            };
          };
          programs.ssh.matchBlocks."*" = {
            identityFile = "/etc/ci-key";
            extraOptions = {
              StrictHostKeyChecking = "no";
              UserKnownHostsFile = "/dev/null";
            };
          };
          programs.ssh.extraConfig = ''
            Host *
              IdentityFile /etc/ci-key
              StrictHostKeyChecking no
              UserKnownHostsFile /dev/null
          '';
        };
        environment.etc."fake-backend.py".text = ''
          import base64
          from http.server import BaseHTTPRequestHandler, HTTPServer

          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  expected = "Basic " + base64.b64encode(b"opencode:secret").decode()
                  if self.headers.get("Authorization") != expected:
                      self.send_response(401)
                      self.send_header("WWW-Authenticate", "Basic")
                      self.end_headers()
                      return
                  self.send_response(200)
                  self.end_headers()
                  self.wfile.write(b"authenticated backend")
              def log_message(self, *_):
                  pass

          HTTPServer(("127.0.0.1", 4096), Handler).serve_forever()
        '';
        environment.etc."legacy-backend.py".text = ''
          from http.server import BaseHTTPRequestHandler, HTTPServer
          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  self.send_response(200)
                  self.end_headers()
                  self.wfile.write(b"legacy backend")
              def log_message(self, *_):
                  pass
          HTTPServer(("127.0.0.1", 4097), Handler).serve_forever()
        '';
        systemd.services.fake-opencode = {
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 /etc/fake-backend.py";
            PrivateNetwork = true;
          };
        };
        systemd.services.legacy-opencode = {
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 /etc/legacy-backend.py";
        };
        systemd.services.client-compat-test = {
          requires = [ "opencode-proxy.service" ];
          after = [ "opencode-proxy.service" ];
          unitConfig.JoinsNamespaceOf = "opencode-proxy.service";
          serviceConfig = {
            PrivateNetwork = true;
            ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.socat}/bin/socat TCP-LISTEN:14096,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/run/opencode/opencode.sock & pid=$!; trap \"kill $pid\" EXIT; sleep 0.2; ${pkgs.curl}/bin/curl -fsS -u opencode:secret http://127.0.0.1:14096/'";
            Type = "oneshot";
          };
        };
        systemd.sockets.opencode-proxy = {
          socketConfig = {
            ListenStream = "/run/opencode/opencode.sock";
            SocketMode = "0600";
            DirectoryMode = "0700";
            SocketUser = "ci";
            SocketGroup = "users";
          };
        };
        systemd.services.opencode-proxy = {
          requires = [
            "opencode-proxy.socket"
            "fake-opencode.service"
          ];
          after = [ "fake-opencode.service" ];
          unitConfig.JoinsNamespaceOf = "fake-opencode.service";
          serviceConfig = {
            PrivateNetwork = true;
            ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:4096";
          };
        };
      };

  };

  testScript = ''
    server.start()
    server.wait_for_unit("multi-user.target")
    server.succeed("systemctl start sshd.service")
    server.succeed("install -d -m 700 -o ci -g users /home/ci/.ssh; install -m 600 -o ci -g users /etc/ci-key /home/ci/.ssh/id_ed25519; ssh-keyscan -H localhost > /home/ci/.ssh/known_hosts; chown ci:users /home/ci/.ssh/known_hosts")
    server.succeed("test -x /home/ci/.nix-profile/bin/opencode-fixture")
    server.succeed("grep -q 'opencode-client-proxy-fixture.service' /home/ci/.nix-profile/bin/opencode-fixture")
    server.succeed("test -x /home/ci/.nix-profile/bin/opencode-fixture && echo GENERATED_WRAPPER_INSTALLED")
    server.succeed("systemctl start fake-opencode.service")
    server.wait_for_unit("fake-opencode.service")
    server.succeed("systemctl start opencode-proxy.socket")
    server.wait_for_unit("opencode-proxy.socket")
    server.succeed("test \"$(stat -c %a /run/opencode/opencode.sock)\" = 600")
    server.succeed("! ss -lnt | grep -q ':4096 '")
    server.succeed("systemctl start opencode-proxy.service")
    server.succeed("systemctl start client-compat-test.service")
    server.succeed("echo CLIENT_PRIVATE_PROXY_OK")
    server.succeed("systemctl start legacy-opencode.service")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:4097/ | grep -q 'legacy backend'")
    server.succeed(
      "sshpass -p ci ssh -N -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
      "-o ExitOnForwardFailure=yes -L 14097:127.0.0.1:4097 ci@localhost "
      "</dev/null >/dev/null 2>&1 &"
    )
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:14097/ | grep -q 'legacy backend'")
    server.succeed(
      "sshpass -p ci ssh -N -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
      "-o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes "
      "-L /run/opencode/client.sock:/run/opencode/opencode.sock ci@localhost "
      "</dev/null >/dev/null 2>&1 &"
    )
    server.wait_until_succeeds("test -S /run/opencode/client.sock")
    server.succeed("test \"$(stat -c %a /run/opencode/client.sock)\" = 600")
    server.succeed("! curl -fsS --unix-socket /run/opencode/client.sock http://localhost/")
    server.succeed("curl -u opencode:secret --unix-socket /run/opencode/client.sock http://localhost/ | grep -q 'authenticated backend'")
  '';
}
