# Remote OpenCode

OpenCode separates its TUI client from a persistent remote backend.

## Backend host (NixOS + Home Manager)

```nix
{
  programs.opencode-nix = {
    enable = true;
    backend = {
      enable = true;
      host = "127.0.0.1";
      port = 4096;
      # Point to a runtime secret (sops-nix works):
      # environmentFile = "/run/user/1000/secrets/opencode";
    };
  };
}
```

Enable lingering for the backend user if you want systemd user services
to survive logouts (`loginctl enable-linger USER`). The remote host
owns the working trees, development tools and session database.

## Laptop (Home Manager)

```nix
{
  programs.opencode-nix = {
    enable = true;
    backend.enable = false;
    client.connections.lab = {
      transport = "ssh";
      sshTarget = "opencode-host";
      localPort = 14096;
      remotePort = 4096;
    };
  };
}
```

Invoke `opencode-lab` on the laptop. That command starts the
`opencode-tunnel-lab.service` user unit, waits for its local TCP
listener, then runs `opencode attach http://127.0.0.1:14096`.

Configure `Host opencode-host` and authentication in your OpenSSH
client configuration. SSH must be able to connect noninteractively
(`BatchMode=yes`) and the backend must be running on the remote host.
To troubleshoot: `journalctl --user -u opencode-tunnel-lab.service`.
The tunnel remains available after the TUI exits; stop it with
`systemctl --user stop opencode-tunnel-lab.service`.

For multiple SSH targets choose a unique `localPort` for each one.
For a direct connection set `transport = "direct"; url = "https://...";`
and use its generated `opencode-<name>` command.

SSH tunnelling keeps the OpenCode service bound to loopback on the host.
Never expose an unauthenticated OpenCode backend directly to the internet.
