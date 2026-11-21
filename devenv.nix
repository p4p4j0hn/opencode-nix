{ pkgs, ... }:

{
  packages = [
    pkgs.nixfmt-tree
    pkgs.black
    pkgs.statix
  ];

  treefmt = {
    enable = true;
    config.programs.nixfmt.enable = true;
  };

  git-hooks.hooks = {
    treefmt.enable = true;
    black.enable = true;
    statix.enable = true;
  };
}
