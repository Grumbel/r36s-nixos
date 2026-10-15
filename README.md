# NixOS for the R36S

Minimal headless NixOS for the R36S (Rockchip RK3326) handheld: mainline
kernel, USB WiFi, SSH.

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

## RetroArch

RetroArch starts on boot on the built-in display (`modules/retroarch.nix`)
and is controlled with the gamepad only:

| Input                         | Action                               |
|-------------------------------|--------------------------------------|
| Select + X                    | open the menu while a game runs      |
| Select + Start                | close the game, back to the menu     |
| Main Menu → Quit RetroArch    | shut the device down                 |
| Power button                  | shut the device down                 |

ROMs go into `/home/nixos/roms`, e.g.
`scp game.gba nixos@r36s.local:roms/`. Only free cores that are in the
NixOS binary cache are included (fceumm, gambatte, mgba, pcsx-rearmed,
beetle-pce-fast, stella).

The buttons and analog sticks are two separate input devices in Linux.
`r36s-gamepad.service` merges them into one virtual "R36S Gamepad"
(`/dev/input/r36s-gamepad`) with evsieve; SDL and RetroArch only see that
one.

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

## Boot time

Boot to RetroArch takes ~30 s (it was ~50 s). The generic NixOS kernel
is tuned for big machines, which hurts on the RK3326:

- **CPU frequency:** `schedutil` with its default rate limit switches
  between 600 and 1296 MHz ~200 times per second, each switch changing
  the CPU voltage over the PMIC's I²C bus. The device boots with the
  `performance` governor and `r36s-cpufreq.service` switches to
  `schedutil` with a 20 ms rate limit once RetroArch is up.
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
