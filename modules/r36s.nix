# Hardware support for the R36S (RK3326) handheld: kernel, device tree,
# boot chain and SD card image layout.
#
# Boot chain: RK3326 boot ROM -> vendor idbloader/U-Boot/trust (raw area
# before the first partition) -> U-Boot `cfgload` reads /boot.ini from the
# FAT partition -> boot.ini runs `sysboot` on the NixOS generated
# /extlinux/extlinux.conf on that same FAT partition.
{
  config,
  lib,
  pkgs,
  modulesPath,
  utils,
  ...
}:

let
  dtbName = "rockchip/rk3326-gameconsole-r36s.dtb";

  r36s-dtbs = pkgs.stdenv.mkDerivation {
    name = "r36s-dtbs-${config.boot.kernelPackages.kernel.version}";
    inherit (config.boot.kernelPackages.kernel) src;
    nativeBuildInputs = [ pkgs.buildPackages.dtc ];
    # Only unpack what is needed to build the device tree
    unpackPhase = ''
      mkdir src && cd src
      tar xf $src --strip-components=1 --wildcards \
        '*/arch/arm64/boot/dts/rockchip/*' '*/include/dt-bindings/*' \
        '*/include/uapi/linux/input-event-codes.h'
    '';
    dontConfigure = true;
    buildPhase = ''
      cp ${../dts/rk3326-gameconsole-r36s.dts} arch/arm64/boot/dts/rockchip/rk3326-gameconsole-r36s.dts
      $CC -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
        -I include -I arch/arm64/boot/dts/rockchip \
        arch/arm64/boot/dts/rockchip/rk3326-gameconsole-r36s.dts \
        | dtc -I dts -O dtb -@ -o r36s.dtb
    '';
    installPhase = ''
      install -Dm644 r36s.dtb $out/${dtbName}
    '';
  };

  # Only ship the firmware for the mt7601u USB WiFi dongle instead of all
  # of linux-firmware.
  gamepadButtons = "/dev/input/by-path/platform-gpio-keys-event-joystick";
  gamepadSticks = "/dev/input/by-path/platform-adc-joystick-event-joystick";
  gamepadDevices = map (p: "${utils.escapeSystemdPath p}.device") [
    gamepadButtons
    gamepadSticks
  ];

  mt7601u-firmware = pkgs.runCommand "mt7601u-firmware" { } ''
    install -Dm644 ${pkgs.linux-firmware}/lib/firmware/mediatek/mt7601u.bin $out/lib/firmware/mediatek/mt7601u.bin
  '';
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    # Kernel messages on the built-in display as well
    "console=tty0"
    # UART2 on the board, as used by U-Boot. Last, so it is /dev/console.
    "console=ttyS2,115200n8"
    "earlycon"
  ];

  # Everything needed to reach the SD card (dw_mmc, rk817 PMIC, pinctrl,
  # i2c, ...) is built into the kernel, the rest are modules.
  boot.initrd.availableKernelModules = [
    "mmc_block"
    "io-domain"
  ];

  # sd-image.nix pulls in modules for every platform, which only bloats
  # the initrd here.
  hardware.enableAllHardware = lib.mkForce false;

  hardware.deviceTree = {
    enable = true;
    name = dtbName;
    dtbSource = r36s-dtbs;
  };

  boot.extraModulePackages = [
    (config.boot.kernelPackages.callPackage ../drivers/panel-generic-dsi { })
  ];

  hardware.firmware = [ mt7601u-firmware ];

  # Mesa with panfrost (Mali-G31) for rendering and rockchip for KMS
  hardware.graphics.enable = true;

  # Buttons (gpio-keys) and sticks (adc-joystick) are two separate input
  # devices, which most software would treat as two gamepads. Merge them
  # into one virtual "R36S Gamepad" and hide the originals.
  services.udev.extraRules = ''
    # Make the gamepad devices visible to systemd, for r36s-gamepad.service,
    # and stop them from showing up as separate (grabbed, so silent)
    # joysticks next to the merged one
    SUBSYSTEM=="input", ENV{ID_PATH}=="platform-gpio-keys|platform-adc-joystick", ENV{ID_INPUT_JOYSTICK}=""
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_PATH}=="platform-gpio-keys|platform-adc-joystick", TAG+="systemd"
  '';

  systemd.services.r36s-gamepad = {
    description = "Merge R36S buttons and sticks into one gamepad";
    wantedBy = [ "multi-user.target" ];
    requires = gamepadDevices;
    after = gamepadDevices;
    serviceConfig = {
      ExecStart = lib.escapeShellArgs [
        "${pkgs.evsieve}/bin/evsieve"
        "--input"
        gamepadButtons
        "grab=force"
        "--input"
        gamepadSticks
        "grab=force"
        "--output"
        "name=R36S Gamepad"
        "create-link=/dev/input/r36s-gamepad"
      ];
      Restart = "always";
      RestartSec = 1;
    };
  };

  # Keep the volume across reboots
  hardware.alsa.enablePersistence = true;

  # Volume buttons
  services.actkbd = {
    enable = true;
    bindings = [
      {
        keys = [ 115 ]; # KEY_VOLUMEUP
        events = [ "key" "rep" ];
        command = "${pkgs.alsa-utils}/bin/amixer -q -c 0 sset Master playback 5%+";
      }
      {
        keys = [ 114 ]; # KEY_VOLUMEDOWN
        events = [ "key" "rep" ];
        command = "${pkgs.alsa-utils}/bin/amixer -q -c 0 sset Master playback 5%-";
      }
    ];
  };

  # Without a keyboard the volume buttons are the only keys reaching the
  # console, where they would type escape sequences (F14/Help).
  systemd.services.console-ignore-volume-keys = {
    description = "Ignore volume keys on the text console";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-vconsole-setup.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      printf 'keycode 114 = VoidSymbol\nkeycode 115 = VoidSymbol\n' \
        | ${pkgs.kbd}/bin/loadkeys -C /dev/tty1 -
    '';
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible = {
    enable = true;
    # The FAT partition holds a kernel + initrd per generation
    configurationLimit = 5;
  };

  # The vendor U-Boot can only load boot.ini from the first (FAT)
  # partition, so that partition is /boot, not the usual /boot/firmware.
  # Mounted by the FAT serial number and not by label, as an ArkOS card in
  # the second slot also has a FAT partition labeled BOOT.
  fileSystems."/boot" = {
    device =
      let
        id = lib.toUpper (lib.removePrefix "0x" config.sdImage.firmwarePartitionID);
      in
      "/dev/disk/by-uuid/${lib.substring 0 4 id}-${lib.substring 4 4 id}";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  sdImage = {
    # Same layout as ArkOS: bootloader in the first 16 MiB, then FAT.
    firmwarePartitionOffset = 16;
    firmwarePartitionName = "BOOT";
    firmwareSize = 512;

    populateFirmwareCommands = ''
      cp ${../bootloader/boot.ini} firmware/boot.ini
      cp ${../bootloader/wpa_supplicant.conf} firmware/wpa_supplicant.conf
      cp ${../bootloader/authorized_keys} firmware/authorized_keys
      # Read by U-Boot itself to initialize the panel and show the logo.
      cp ${../bootloader/rg351mp-kernel.dtb} firmware/rg351mp-kernel.dtb
      cp ${../bootloader/logo.bmp} firmware/logo.bmp
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./firmware
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
    '';

    # Rockchip boot ROM loads idbloader from sector 64, the miniloader then
    # loads U-Boot and trust from fixed offsets.
    postBuildCommands = ''
      dd if=${../bootloader/idbloader.img} of=$img conv=notrunc bs=512 seek=64
      dd if=${../bootloader/uboot.img} of=$img conv=notrunc bs=512 seek=16384
      dd if=${../bootloader/trust.img} of=$img conv=notrunc bs=512 seek=28672
    '';
  };
}
