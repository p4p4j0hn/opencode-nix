{
  description = "OpenCode upstream binaries and optional Home Manager backend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
      packageFor = pkgs: pkgs.callPackage ./pkgs/opencode.nix {};
    in {
      packages = eachSystem (pkgs: {
        default = packageFor pkgs;
        opencode = packageFor pkgs;
      });
      apps = eachSystem (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/opencode";
        };
      });
      overlays.default = final: prev: {
        opencode = packageFor final;
      };
      homeManagerModules.default = import ./modules/home-manager.nix self;
      homeManagerModules.opencode = self.homeManagerModules.default;
      checks = eachSystem (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });
    };
}
