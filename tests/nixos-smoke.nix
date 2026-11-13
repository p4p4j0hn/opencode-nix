{ pkgs }:
pkgs.testers.nixosTest {
  name = "opencode-nixos-smoke";
  nodes.smoke = { ... }: {
    services.getty.autologinUser = "root";
  };
  testScript = ''
    smoke.start()
    smoke.wait_for_unit("multi-user.target")
    smoke.succeed("true")
  '';
}
