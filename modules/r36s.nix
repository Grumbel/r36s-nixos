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

  gamepadButtons = "/dev/input/by-path/platform-gpio-keys-event-joystick";
  gamepadSticks = "/dev/input/by-path/platform-adc-joystick-event-joystick";
  gamepadDevices = map (p: "${utils.escapeSystemdPath p}.device") [
    gamepadButtons
    gamepadSticks
  ];

  # FN + D-pad up/down. 5 % steps on a squared scale, so the steps look
  # even, and never below 1 % (raw 17 of 1666), which is still readable.
  brightness =
    dir:
    "${pkgs.brightnessctl}/bin/brightnessctl -q -e2 -n17 set 5%${if dir == "up" then "+" else "-"}";

  # udev looks up a module for every device tree device, which is very slow
  # with the generic kernel's huge alias list. Only allow the lookup for
  # the compatibles of this board that actually have a module. This
  # replaces systemd's 80-drivers.rules, see scripts/of-kmod-rules.py.
  ofKmodRules = pkgs.runCommand "r36s-of-kmod-rules" {
    nativeBuildInputs = [
      pkgs.buildPackages.python3
      pkgs.buildPackages.dtc
    ];
  } ''
    dtc -I dtb -O dts -q ${r36s-dtbs}/${dtbName} -o board.dts
    mkdir -p $out/lib/udev/rules.d
    python3 ${../scripts/of-kmod-rules.py} board.dts \
      ${config.system.modulesTree}/lib/modules/*/modules.alias \
      ${config.systemd.package}/lib/udev/rules.d/80-drivers.rules \
      > $out/lib/udev/rules.d/80-drivers.rules
  '';

  # Files on the FAT partition that are read by U-Boot itself
  ubootFiles = pkgs.linkFarm "r36s-uboot-files" [
    {
      name = "boot.ini";
      path = ../bootloader/boot.ini;
    }
    # Used by U-Boot to initialize the panel for the boot logo
    {
      name = "rg351mp-kernel.dtb";
      path = ../bootloader/rg351mp-kernel.dtb;
    }
    {
      name = "logo.bmp";
      path = pkgs.callPackage ../pkgs/boot-logo { };
    }
  ];

  # The R36S has no built-in WiFi. Ship the firmware of all USB WiFi
  # drivers (~8 MB compressed) instead of all of linux-firmware (~800 MB),
  # see scripts/usb-wifi-firmware.sh.
  wifi-firmware =
    pkgs.runCommand "r36s-usb-wifi-firmware" { nativeBuildInputs = [ pkgs.buildPackages.kmod ]; }
      ''
        bash ${../scripts/usb-wifi-firmware.sh} ${config.system.modulesTree} \
          ${config.boot.kernelPackages.kernel.modDirVersion} \
          ${pkgs.linux-firmware}/lib/firmware $out/lib/firmware
      '';
in
{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    # UART2 on the board, as used by U-Boot: kernel messages and a getty
    "console=ttyS2,115200n8"
    "earlycon"
    # The built-in display. Last, so it is /dev/console and also gets the
    # systemd boot status messages.
    "console=tty0"
    # Boot at full speed, see r36s-cpufreq.service
    "cpufreq.default_governor=performance"
  ];

  # Everything needed to reach the SD card (dw_mmc, rk817 PMIC, pinctrl,
  # i2c, ...) is built into the kernel, the rest are modules.
  boot.initrd.availableKernelModules = [
    "io-domain"
  ];

  # Load these right away instead of waiting for udev, which only gets to
  # them many seconds later: the SD card block device for the root file
  # system, and the display, so boot messages show up on screen as soon as
  # possible instead of only when stage 2 is mostly done.
  boot.initrd.kernelModules = [
    "mmc_block"
    "rockchipdrm"
    "phy-rockchip-inno-dsidphy"
    "panel-generic-dsi"
    "pwm_bl"
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

  hardware.firmware = [ wifi-firmware ];

  # Mesa with panfrost (Mali-G31) for rendering and rockchip for KMS
  hardware.graphics.enable = true;

  # Buttons (gpio-keys) and sticks (adc-joystick) are two separate input
  # devices, which most software would treat as two gamepads. Merge them
  # into one virtual "R36S Gamepad" and hide the originals.
  # schedutil with its default rate limit (the 107 us transition latency)
  # switches between 600 and 1296 MHz ~200 times per second, every switch
  # changing the CPU voltage over the PMIC's I2C bus. That eats a good part
  # of the CPU and slows down the boot considerably. Boot with the
  # performance governor, then switch to schedutil with a sane rate limit.
  systemd.services.r36s-cpufreq = {
    description = "Switch to the schedutil CPU frequency governor";
    wantedBy = [ "multi-user.target" ];
    after = [
      "retroarch.service"
      "es-de.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      echo schedutil > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
      echo 20000 > /sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us
    '';
  };

  # The udev coldplug replays an event for every module and driver the
  # generic kernel knows about, built-in ones included: ~2600 of ~3200
  # events, which take the RK3326 ~10 s to work through in each boot stage.
  # Nothing needs them except the module events systemd uses for the
  # configfs and fuse mounts.
  systemd.services.systemd-udev-trigger.serviceConfig.ExecStart = [
    ""
    "-udevadm trigger --type=all --action=add --prioritized-subsystem=block,tpmrm,net,tty,input --subsystem-nomatch=module --subsystem-nomatch=drivers"
    "-udevadm trigger --action=add --subsystem-match=module --sysname-match=configfs --sysname-match=fuse"
  ];
  boot.initrd.systemd.services.systemd-udev-trigger.serviceConfig.ExecStart = [
    ""
    "-udevadm trigger --type=all --action=add --prioritized-subsystem=block,tpmrm,net,tty,input --subsystem-nomatch=module --subsystem-nomatch=drivers"
  ];

  # mkAfter: must come after the 80-drivers.rules it replaces
  services.udev.packages = lib.mkAfter [ ofKmodRules ];
  boot.initrd.services.udev.packages = lib.mkAfter [ ofKmodRules ];

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
        # Brightness. sequential: FN must be held first, so the D-pad
        # alone is never withheld and stays lag free. The D-pad presses
        # that change the brightness don't reach the games.
        "--hook"
        "btn:mode"
        "btn:dpad_up"
        "sequential"
        "exec-shell=${brightness "up"}"
        "--hook"
        "btn:mode"
        "btn:dpad_down"
        "sequential"
        "exec-shell=${brightness "down"}"
        "--withhold"
        "btn:dpad_up"
        "btn:dpad_down"
        "--output"
        "name=R36S Gamepad"
        "create-link=/dev/input/r36s-gamepad"
      ];
      Restart = "always";
      RestartSec = 1;
    };
  };

  # The power LED is blue and turns red when the battery is low, like in
  # ArkOS: solid red at 20 % and below, blinking at 10 % and below. Not
  # while the DC charger is plugged in; the rk817 doesn't see the separate
  # charger IC and reports "Discharging" even then.
  systemd.services.r36s-battery-led = {
    description = "Low battery warning on the power LED";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Restart = "always";
    script = ''
      led=/sys/class/leds/red:power
      state=
      while true; do
        capacity=$(cat /sys/class/power_supply/rk817-battery/capacity)
        online=$(cat /sys/class/power_supply/dc-charger/online)
        if [ "$online" = 1 ] || [ "$capacity" -gt 20 ]; then
          new=none
        elif [ "$capacity" -gt 10 ]; then
          new=default-on
        else
          new=timer
        fi
        # Setting the trigger restarts the blinking, only do it on changes
        if [ "$new" != "$state" ]; then
          echo "$new" > $led/trigger
          [ "$new" = none ] && echo 0 > $led/brightness
          state=$new
        fi
        sleep 30
      done
    '';
  };

  # Power button: short press suspends, holding it for 5 s (logind's fixed
  # long press time) powers off. Deep suspend resumes fine, the rk805
  # power key is a wakeup source.
  services.logind.settings.Login = {
    HandlePowerKey = "suspend";
    HandlePowerKeyLongPress = "poweroff";
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

  # nixos-rebuild only updates extlinux.conf and the kernels on /boot, keep
  # the files read by U-Boot up to date as well. User files on /boot
  # (wpa_supplicant.conf, authorized_keys) are left alone.
  systemd.services.r36s-boot-files = {
    description = "Update U-Boot files on /boot";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/boot";
    path = [ pkgs.diffutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for f in ${ubootFiles}/*; do
        n=$(basename "$f")
        if ! cmp -s "$f" "/boot/$n"; then
          echo "updating /boot/$n"
          cp -L "$f" "/boot/$n.tmp"
          mv "/boot/$n.tmp" "/boot/$n"
        fi
      done
      sync /boot
    '';
  };

  sdImage = {
    # Same layout as ArkOS: bootloader in the first 16 MiB, then FAT.
    firmwarePartitionOffset = 16;
    firmwarePartitionName = "BOOT";
    firmwareSize = 512;

    populateFirmwareCommands = ''
      cp -L ${ubootFiles}/* firmware/
      cp ${../bootloader/wpa_supplicant.conf} firmware/wpa_supplicant.conf
      cp ${../bootloader/authorized_keys} firmware/authorized_keys
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
