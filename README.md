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
display init.

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
