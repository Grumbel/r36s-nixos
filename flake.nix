{
  description = "NixOS for the R36S (RK3326) handheld";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    {
      nixosConfigurations.r36s = nixpkgs.lib.nixosSystem {
        modules = [
          ./modules/r36s.nix
          ./configuration.nix
        ];
      };

      nixosModules.r36s = ./modules/r36s.nix;

      # The image is built natively for aarch64-linux, an x86_64 host needs
      # `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` for that.
      packages =
        nixpkgs.lib.genAttrs
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
          (system: {
            default = self.packages.${system}.sdImage;
            sdImage = self.nixosConfigurations.r36s.config.system.build.sdImage;
            dtbs = self.nixosConfigurations.r36s.config.hardware.deviceTree.package;
          });
    };
}
