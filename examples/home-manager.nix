{ inputs, ... }: {
  imports = [ inputs.opencode-nix.homeManagerModules.default ];
  programs.opencode-nix = {
    enable = true;
    settings = {
      compaction = {
        auto = true;
        keep.tokens = 24000;
        buffer = 24000;
      };
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
