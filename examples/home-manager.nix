{ inputs, ... }: {
  imports = [ inputs.opencode-nix.homeManagerModules.default ];
  programs.opencode-nix = {
    enable = true;
    settings = {
      compaction = { auto = true; prune = false; reserved = 10000; };
    };
    backend = {
      enable = true;
      host = "127.0.0.1";
      port = 4096;
      # Optional: point at a runtime secret file from sops-nix.
      # environmentFile = "/run/user/1000/secrets/opencode";
    };
  };
}
