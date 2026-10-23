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

  # SSH keys are read from authorized_keys on the FAT boot partition, so
  # the image contains no personal keys and they can be added from a PC
  # after flashing.
  services.openssh = {
    enable = true;
    authorizedKeysFiles = [ "/boot/authorized_keys" ];
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
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
      "render"
    ];
    # For logging in on the serial console, SSH only accepts keys.
    initialPassword = "nixos";
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
    alsa-utils
    evtest
    htop
    i2c-tools
    (callPackage ./pkgs/sdl2-demo { })
    iw
    usbutils
    wpa_supplicant

    libarchive
    unzip
    _7zz
  ];

  documentation.enable = false;

  system.stateVersion = "26.05";
}
