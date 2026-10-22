# Import inputs.opencode-nix.homeManagerModules.default in your HM modules.
_: {
  programs.opencode-nix = {
    enable = true;
    backend.enable = false;
    client.connections = {
      # Runs 'opencode-lab', opening an on-demand systemd user SSH tunnel.
      lab = {
        transport = "ssh";
        sshTarget = "opencode-host"; # OpenSSH host alias
        localPort = 14096;
        remotePort = 4096;
      };
      # Direct access should use HTTPS with authentication on a trusted network.
      private = {
        transport = "direct";
        url = "https://opencode.example.internal";
      };
    };
  };
}
