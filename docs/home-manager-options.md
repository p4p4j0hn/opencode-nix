# Home Manager OpenCode options

The `programs.opencode-nix` module uses the **native Home Manager**
`programs.opencode` module for standard OpenCode functionality and pins
the `opencode-nix` flake's prebuilt binary as the package.

The following standard options are supported, with identical types and
behavior to Home Manager **release-26.05**:

| `programs.opencode-nix.*` | Meaning |
|---|---|
| `enable`, `package`, `settings` | Program and JSON settings (mapped to native Home Manager) |
| `extraPackages` | Additional tools placed on OpenCode's PATH |
| `enableMcpIntegration` | Merge `programs.mcp.servers` into OpenCode's MCP config |
| `tui` | Separate `tui.json`, including theme and keybinds |
| `web.enable`, `web.extraArgs`, `web.environmentFile` | Native web service |
| `context` | Global `AGENTS.md` |
| `commands` | Custom commands |
| `agents` | Custom agents |
| `skills` | Custom skills |
| `themes` | Custom themes |
| `tools` | Custom tools |

The project-specific extensions are `backend.*` (the existing
persistent systemd user service), `client.connections.*` (named remote
clients), and `recoverySkill.enable`.

The built-in compaction recovery skill is added via `skills` and can
be overridden or disabled. Do not enable both `web.enable` and
`backend.enable` on the same account unless they are assigned different
listen ports.

## Example

```nix
{
  programs.opencode-nix = {
    enable = true;
    extraPackages = [ pkgs.git pkgs.ripgrep ];
    enableMcpIntegration = true;
    settings = {
      model = "provider/model";
      autoupdate = false;
    };
    tui = {
      theme = "system";
      keybinds.leader = "alt+b";
    };
    context = "Use conventional commit messages.";
    commands.review = "Review this change for correctness and security.";
    agents.reviewer = "You are a rigorous code reviewer.";
    skills.team = ./skills/team/SKILL.md;
    themes.custom = ./themes/custom.json;
    tools.my-tool = ./tools/my-tool.ts;
    backend.enable = false;
  };
}
```

### Version alignment

Unlike copying the Home Manager module, this approach inherits the exact
upstream features and behavior supplied by the pinned Home Manager input.
Home Manager `master` may expose newer options absent in `release-26.05`
(for example `validateFiles`); those are not claimed to be supported
by this release-pinned flake until the upstream version provides them.
