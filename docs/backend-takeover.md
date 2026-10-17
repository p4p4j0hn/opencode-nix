# Backend port takeover (Linux)

Normally the Home Manager `opencode-backend.service` starts `opencode serve`
without terminating any existing processes. To reclaim a port held by an
orphaned, same-user OpenCode server, enable:

```nix
programs.opencode-nix = {
  enable = true;
  backend = {
    enable = true;
    host = "127.0.0.1";
    port = 4096;
    takeover = {
      enable = true; # OFF by default
      graceSeconds = 5;
    };
  };
};
```

Before each service start, a short `ExecStartPre` check uses `lsof` to find
listeners on the configured port and validates each listener through
Linux `/proc`. It will only signal processes owned by the same user whose
command line identifies `opencode serve --port 4096` (or
`--port=4096`). It sends SIGTERM, waits for the grace period, and uses
SIGKILL only if the same validated process remains listening.

**Safety constraints:** An unknown listener makes the service fail closed;
no unrelated process is killed. This option only applies to Linux and does
not discover servers on other ports, terminate desktop or TUI sessions, or
guarantee that a new process cannot race to acquire the port. An explicitly
configured OpenCode server owned by the same user on the same port is
considered eligible for takeover even if it was deliberately started.
Keep takeover disabled if multiple independently managed servers share
an account or port.

Unit tests mock process discovery and signals and do not kill real processes.
