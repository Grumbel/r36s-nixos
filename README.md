# NixOS for the R36S

NixOS for the R36S (Rockchip RK3326) handheld: mainline kernel, ES-DE and
RetroArch on the built-in display, USB WiFi, SSH.

## Build

The image is built natively for `aarch64-linux`, so an x86_64 host needs
binfmt emulation (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`).
Almost everything comes from the binary cache.

    nix build .#sdImage

## Flash

    zstd -dc result/sd-image/nixos-image-*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

Then mount the `BOOT` (FAT) partition and

- add your WiFi network to `wpa_supplicant.conf`
- add your SSH public key to `authorized_keys`

The image itself contains no credentials. The root partition grows to fill
the card on first boot.

## Log in

    ssh nixos@r36s.local

SSH only accepts the keys from `authorized_keys` on the boot partition.
The `nixos` user's password, `nixos`, only works on the serial console
(UART2, 115200 8N1).

## Update

    nixos-rebuild switch --flake .#r36s --target-host nixos@r36s.local --sudo

## How it boots

| Location                 | Content                                                  |
|--------------------------|----------------------------------------------------------|
| sector 64                | `bootloader/idbloader.img` (DDR init + miniloader)       |
| sector 16384             | `bootloader/uboot.img` (Hardkernel U-Boot 2017.09)       |
| sector 28672             | `bootloader/trust.img` (BL31 + OP-TEE)                   |
| partition 1, FAT, `BOOT` | `boot.ini`, `extlinux/`, kernels/initrds, U-Boot's panel DTB + logo |
| partition 2, ext4        | NixOS root                                               |

The bootloader blobs were taken from an R36S running ArkOS. U-Boot runs
`/boot.ini`, which chains into `sysboot` on the NixOS generated
`/extlinux/extlinux.conf`, so generations and rollback work as usual.
`rg351mp-kernel.dtb` and `logo.bmp` are only used by U-Boot for its own
display init. The logo is generated from the NixOS snowflake
(`pkgs/boot-logo`). `r36s-boot-files.service` keeps `boot.ini`, the logo
and the U-Boot DTB on `/boot` up to date after `nixos-rebuild`.

The kernel device tree, `dts/rk3326-gameconsole-r36s.dts`, is mainline's
ODROID-GO Super tree plus R36S fixes (OTG VBUS, second SD slot, PMIC
restart).

## Display

Mainline has no driver for the R36S panels, so the built-in display uses
ROCKNIX's `panel-generic-dsi` (`drivers/panel-generic-dsi`), built as an
out-of-tree module. The panel's init sequence and timings are in the
`panel_description` property in the DTS. They currently describe the
original panel ("Panel 0" in ArkOS), converted from the vendor DTB. Other
panel revisions need their own description, which can be converted the
same way from the matching ArkOS `ScreenFiles/Panel N` DTB.

## Games

The device boots into [ES-DE](https://es-de.org) (`modules/es-de.nix`),
which launches the games in RetroArch (`modules/retroarch.nix`). With
`r36s.frontend = "retroarch";` it boots straight into RetroArch instead.
Everything is controlled with the gamepad:

| Input                         | Action                                   |
|-------------------------------|------------------------------------------|
| A / B                         | ES-DE: select / back                     |
| Start / Select                | ES-DE: main menu / game options          |
| Start → Quit                  | ES-DE: power off, reboot or suspend      |
| Select + X                    | RetroArch menu while a game runs         |
| Select + Start                | quit the game, back to ES-DE (RetroArch only: back to its menu) |
| Select + R1 / L1              | save / load state                        |
| Select + D-pad left / right   | previous / next state slot               |
| Select + R2                   | fast forward on/off                      |
| Select + A                    | pause                                    |
| Select + Y                    | screenshot                               |
| FN + D-pad up / down          | brightness                               |
| Volume buttons                | volume                                   |
| Power button                  | suspend, press again to wake up          |
| Power button, hold 5 s        | shut the device down                     |

With RetroArch as the front end, Main Menu → Quit RetroArch shuts the
device down.

ROMs go into `/roms`, one directory per system as ES-DE names them
(`gba`, `snes`, `megadrive`, `psx`, …), e.g.
`scp game.gba nixos@r36s.local:/roms/gba/`. To keep them elsewhere, mount
a partition or the second SD card on `/roms` (`r36s.retroarch.romDirectory`
changes the path). ES-DE only lists systems that have ROMs and an
installed core. ES-DE rescans the ROM directories on every start: with
~10000 games that takes ~15 s.

The default cores are free and in the NixOS binary cache: atari800,
beetle-ngp, beetle-pce-fast, beetle-wswan, bluemsx, dosbox-pure, fceumm,
gambatte, gpsp, handy, mgba, pcsx-rearmed, prboom, prosystem, stella,
tic80 and vecx. GBA games default to gpsp, which is about 2.7 times faster
than mgba on the RK3326. Mega Drive and SNES cores are all unfree in
nixpkgs; `r36s.retroarch.unfreeCores = true;` adds picodrive,
genesis-plus-gx, snes9x2005-plus and snes9x2010, which are then built
locally. `r36s.retroarch.cores` replaces the list.

GLSL shaders and CPU video/audio filters are installed the Nix way: packages
under `pkgs/libretro-*`, paths set in RetroArch settings, nothing copied into
`~/.config/retroarch/`. Default is the full libretro GLSL set plus
Sharp-Shimmerless (same content dArkOS ships). `r36s.retroarch.shaders =
"minimal";` keeps only nearest/bilinear, scanlines, handheld, interpolation,
pixel-art-scaling and Sharp-Shimmerless; `"none"` skips shaders.
`r36s.retroarch.filters = false;` skips the CPU filter packs. Load a preset
from Quick Menu → Shaders while a game is running.

Native games can be added to ES-DE's "Ports" system, Select + Start
quits them:

    r36s.es-de.ports.SuperTux.command = "${pkgs.supertux}/bin/supertux2 --fullscreen";

They are started with `SDL_GAMECONTROLLERCONFIG` set to the R36S mapping
(buttons by label, A is the right button), so SDL games see the gamepad
like under ArkOS/PortMaster. Their output goes to the journal
(`journalctl -t SuperTux`). `r36s.retroarch.settings` adds RetroArch
settings.

The power LED is blue and turns red when the battery is at 20 % or less,
blinking at 10 % or less (`r36s-battery-led.service`). The red charging
LED next to it is controlled by the charger.

The buttons and analog sticks are two separate input devices in Linux.
`r36s-gamepad.service` merges them into one virtual "R36S Gamepad"
(`/dev/input/r36s-gamepad`) with evsieve; SDL and RetroArch only see that
one. evsieve also handles the brightness hotkeys; the D-pad presses that
change the brightness don't reach the games.

### Analog stick range

The sticks are read by the upstream `adc-joystick` driver, which reports
the raw 10-bit ADC value with a fixed range from the device tree
(`abs-range` in `dts/rk3326-gameconsole-r36s.dts`). Unlike ArkOS's
vendor driver, it does not calibrate the center at boot. The range is
262-762, ±250 around 512. The sticks rest at ~505-525 and their travel is
not symmetric: one R36S measured 4-85 at the low end but only 786-884
at the high end. Travel beyond the range is clamped by SDL and RetroArch.

If a stick doesn't reach full deflection in some direction, or reaches
it too early, change `abs-range` and reboot. Narrower ranges reach full
deflection sooner but give less fine control. ArkOS reaches full
deflection only ~128 counts from the center. To see what your sticks
actually do, poll the raw values while moving them (`evtest` can't
read the device while `r36s-gamepad.service` grabs it):

    while true; do cat /sys/bus/iio/devices/iio:device1/in_voltage{0,1,2,3}_raw | tr '\n' ' '; echo; done

The channels are left X, right X, left Y, right Y.

## Your own configuration

To keep your own configuration in a separate flake, import the modules
instead of forking:

    inputs.r36s-nixos.url = "github:Grumbel/r36s-nixos";

    nixosConfigurations.r36s = r36s-nixos.inputs.nixpkgs.lib.nixosSystem {
      modules = [
        r36s-nixos.nixosModules.default        # hardware, RetroArch, ES-DE
        r36s-nixos.nixosModules.configuration  # WiFi, SSH, user of this image
        ./configuration.nix                    # your changes
      ];
    };

## Boot time

Boot to RetroArch takes ~30 s (it was ~50 s). The generic NixOS kernel
is tuned for big machines, which hurts on the RK3326:

- **CPU frequency:** `schedutil` with its default rate limit switches
  between 600 and 1296 MHz ~200 times per second, each switch changing
  the CPU voltage over the PMIC's I²C bus. The device boots with the
  `performance` governor and `r36s-cpufreq.service` switches to
  `schedutil` with a 20 ms rate limit once the front end is up.
- **udev coldplug:** ~2600 of ~3200 coldplug events are for the
  thousands of (mostly built-in) modules and drivers of the generic
  kernel. `systemd-udev-trigger` skips the `module` and `drivers`
  subsystems, except for the `configfs` and `fuse` module events systemd
  needs.
- **Module lookups:** a kmod lookup of a device tree modalias has to
  match ~18000 wildcard aliases. `scripts/of-kmod-rules.py` replaces
  systemd's `80-drivers.rules` with one that only does the lookup for the
  compatibles of this board's DTB that actually have a module.
- `mmc_block` and the display stack are loaded right away in the initrd.
