{ pkgs, ... }:

{
  packages = [
    pkgs.nixfmt-tree
    pkgs.black
    pkgs.statix
  ];

  git-hooks.hooks = {
    nix-format = {
      enable = true;
      entry = "nix fmt -- --ci .";
      language = "system";
      pass_filenames = false;
    };
    black.enable = true;
    statix.enable = true;
  };
}
