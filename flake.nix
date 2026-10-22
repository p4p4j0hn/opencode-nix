{
  description = "OpenCode upstream binaries and optional Home Manager backend";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
      packageFor = pkgs: pkgs.callPackage ./pkgs/opencode.nix { };
    in
    {
      packages = eachSystem (pkgs: {
        default = packageFor pkgs;
        opencode = packageFor pkgs;
      });
      formatter = eachSystem (pkgs: pkgs.nixfmt-tree);
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt-tree
            pkgs.black
            pkgs.statix
          ];
        };
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
      checks = eachSystem (
        pkgs:
        {
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        }
        // nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          takeover-unit-tests =
            pkgs.runCommand "opencode-takeover-unit-tests"
              {
                nativeBuildInputs = [ pkgs.python3 ];
                src = ./.;
              }
              ''
                cd "$src"
                python3 -m unittest discover -s tests -p 'test_*.py' -v
                touch "$out"
              '';
          home-manager-module = import ./tests/home-manager.nix {
            inherit pkgs home-manager;
            module = self.homeManagerModules.default;
          };
        }
      );
    };
}
