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

Then mount the `BOOT` (FAT) partition and add your WiFi network to
`wpa_supplicant.conf`. The root partition grows to fill the card on first
boot.

## Log in

    ssh nixos@r36s.local

The `nixos` user's SSH keys are in `configuration.nix`. Its password,
`nixos`, only works on the serial console (UART2, 115200 8N1).

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
ODROID-GO Super tree plus R36S fixes (OTG VBUS, second SD slot). The
display is disabled for now because mainline has no driver for the R36S
panels.
