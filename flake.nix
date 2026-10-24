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
          self.nixosModules.default
          self.nixosModules.configuration
        ];
      };

      # For flakes that build their own R36S system on top of this one:
      # `default` is the hardware support and the front ends,
      # `configuration` the WiFi/SSH/user setup of the image built here.
      nixosModules = {
        default.imports = [
          self.nixosModules.r36s
          self.nixosModules.retroarch
          self.nixosModules.es-de
        ];
        r36s = ./modules/r36s.nix;
        retroarch = ./modules/retroarch.nix;
        es-de = ./modules/es-de.nix;
        configuration = ./configuration.nix;
      };

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
