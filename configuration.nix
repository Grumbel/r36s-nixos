# Minimal headless system: WiFi + SSH.
{ pkgs, ... }:

{
  networking.hostName = "r36s";

  # Networks are read from wpa_supplicant.conf on the FAT boot partition,
  # so they can be set up from a PC after flashing.
  networking.wireless = {
    enable = true;
    extraConfigFiles = [ "/boot/wpa_supplicant.conf" ];
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Reachable as r36s.local
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "audio"
      "input"
    ];
    # For logging in on the serial console, SSH only accepts keys.
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };

  environment.systemPackages = with pkgs; [
    evtest
    htop
    i2c-tools
    iw
    usbutils
    wpa_supplicant
  ];

  documentation.enable = false;

  system.stateVersion = "26.05";
}
