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
      # Optional: runtime mode-600 file containing OPENCODE_PASSWORD.
      # passwordFile = "/home/me/.config/opencode/server-password";
    };
  };
}
```

Invoke `opencode-lab` on the laptop. That command starts the
`opencode-tunnel-lab.service` user unit, waits for its local TCP
listener, then runs `opencode --server http://127.0.0.1:14096`.

Configure `Host opencode-host` and authentication in your OpenSSH
client configuration. SSH must be able to connect noninteractively
(`BatchMode=yes`) and the backend must be running on the remote host.
To troubleshoot: `journalctl --user -u opencode-tunnel-lab.service`.
The tunnel remains available after the TUI exits; stop it with
`systemctl --user stop opencode-tunnel-lab.service`.

For multiple SSH targets choose a unique `localPort` for each one.
For a direct connection set `transport = "direct"; url = "https://...";`
and use its generated `opencode-<name>` command. Set `passwordFile` when the
server requires a password.

SSH tunnelling keeps the OpenCode service bound to loopback on the host.
Never expose an unauthenticated OpenCode backend directly to the internet.

## Private Unix-socket transport

For hosts where even a loopback TCP listener must not exist in the host
namespace, enable the opt-in private backend:

```nix
backend.privateSocket.enable = true;
```

The backend then runs in a private systemd network namespace and is exposed
through the user-owned, mode-`0600` socket
`$XDG_RUNTIME_DIR/opencode/opencode.sock`. The socket directory is mode `0700`.

Use the Unix-socket SSH transport from a client:

```nix
client.connections.lab = {
  transport = "ssh-unix";
  sshTarget = "opencode-host";
  remoteSocket = "/run/user/1000/opencode/opencode.sock";
  localPort = 14096;
};
```

The remote SSH daemon must permit Unix-domain forwarding with
`AllowStreamLocalForwarding yes`; a more specific `Match` block must not
override it with `no`. Verify the socket with `stat` and verify that the
backend port is absent from the host namespace with `ss -lnt`.
