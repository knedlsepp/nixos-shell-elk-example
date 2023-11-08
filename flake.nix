{
  description = "Example flake for a development environment that runs ELK";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixos-shell.url = "github:mic92/nixos-shell";
  };

  outputs = { self, nixpkgs, nixos-shell }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [
        "x86_64-linux"
      ];
      forAllSystems = f: lib.genAttrs supportedSystems (system: f system);
      nixpkgsFor = lib.genAttrs supportedSystems (system: nixpkgs.legacyPackages."${system}");
    in
    {

      nixosModules.development-vm = import ./development-vm.nix;

      devShell = forAllSystems (system:
        nixpkgsFor."${system}".mkShell {
          buildInputs = [
            nixos-shell.defaultPackage."${system}"
          ];
        }
      );

      packages = forAllSystems (system: {
        nixos-vm =
          let
            nixos = lib.nixosSystem {
              inherit system;
              modules = [
                self.nixosModules.development-vm
              ];
            };
          in
          nixos.config.system.build.vm;
      });

      apps = forAllSystems (system: {
        nixos-shell = {
          type = "app";
          program = builtins.toString (nixpkgs.legacyPackages."${system}".writeScript "nixos-shell" ''
            ${nixos-shell.defaultPackage."${system}"}/bin/nixos-shell \
              --flake ${self}#development-vm
          '');
        };
      });

    };
}
