{ pkgs, ... }:

{
  packages = [
    pkgs.nixfmt-tree
    pkgs.black
    pkgs.statix
  ];
}
