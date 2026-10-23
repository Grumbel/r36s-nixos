# AGENTS.md

NixOS flake for the R36S handheld (Rockchip RK3326, Mali-G31, aarch64).
Mainline kernel (`linuxPackages_latest`), vendor bootloader blobs from
ArkOS, RetroArch as the front end. `README.md` is the user-facing
documentation, `UPSTREAM.md` lists upstream bugs found along the way.

## Layout

| Path                         | What                                                      |
|------------------------------|-----------------------------------------------------------|
| `flake.nix`                  | `nixosConfigurations.r36s`, `packages.*.sdImage`/`dtbs`   |
| `modules/r36s.nix`           | hardware: kernel, DTB, firmware, boot chain, SD image, gamepad merge, boot-time tuning |
| `modules/retroarch.nix`      | RetroArch on tty1, gamepad autoconfig, cores              |
| `configuration.nix`          | the "user" part: WiFi, SSH, users, packages               |
| `dts/rk3326-gameconsole-r36s.dts` | kernel device tree, builds on mainline `rk3326-odroid-go3.dts` |
| `drivers/panel-generic-dsi/` | out-of-tree ROCKNIX panel driver for the built-in display |
| `bootloader/`                | idbloader/U-Boot/trust blobs, `boot.ini`, U-Boot's panel DTB, templates for `/boot` |
| `pkgs/`                      | boot logo, SDL2 demo                                      |
| `scripts/of-kmod-rules.py`   | generates the trimmed `80-drivers.rules`                  |

## Build and deploy

The host is x86_64 with binfmt emulation for aarch64, so anything that
isn't in the binary cache builds slowly. Avoid changes that force a
kernel rebuild (kernel config, patches) unless really needed; DTS
changes and out-of-tree modules are cheap.

    nix build .#sdImage                       # SD card image
    nix build .#dtbs                          # just the device tree
    nix build .#nixosConfigurations.r36s.config.system.build.toplevel
    nixos-rebuild switch --flake .#r36s --target-host nixos@r36s.local --sudo

The flake only sees files tracked by git: `git add` new files before
building. DTB and kernel changes need a reboot (`ssh nixos@r36s.local sudo reboot`).
To check that a change actually reached the device, compare
`readlink /run/current-system` there with the local build.

## The device

- SSH: `nixos@r36s.local` (key auth, passwordless sudo).
- Serial console: UART2, 115200 8N1, login `nixos`/`nixos`. Use it when
  the device doesn't come up on the network.
- An ArkOS card may sit in the second SD slot (`mmcblk1`), its FAT is also
  labeled `BOOT`. Useful as a reference for vendor DTBs and drivers.
- Ask the user to press reset if the device hangs; it has no other
  out-of-band control.
- The only USB port is the OTG port (dwc2, host mode); USB WiFi dongles
  go there. There is no built-in WiFi.

## Conventions

- Keep the system small: the SD card is slow and every boot second
  counts. Ship only the firmware that is needed (see
  `scripts/usb-wifi-firmware.sh`) instead of all of `linux-firmware`,
  don't enable things that pull in large closures without a reason.
- Comments explain *why* (hardware quirk, measured numbers, upstream
  bug), in plain sentences. Match the existing style in `.nix` and `.dts`.
- Workarounds for upstream bugs get an entry in `UPSTREAM.md`: the bug,
  the fix, the workaround used here, where to send it.
- User-visible behavior (buttons, boot time, setup steps) is documented
  in `README.md`.
- Nix code follows `nixfmt` style (not enforced, `modules/r36s.nix` has
  a few unformatted spots).
- Commits: short imperative subject ("Fix ...", "Show ..."), body
  explains why and gives numbers where there are some. Commit only when
  asked.
