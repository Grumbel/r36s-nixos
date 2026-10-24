# AGENTS.md

NixOS flake for the R36S handheld (Rockchip RK3326, Mali-G31, aarch64).
Mainline kernel (`linuxPackages_latest`), vendor bootloader blobs from
ArkOS, ES-DE as the front end launching RetroArch. `README.md` is the user-facing
documentation, `UPSTREAM.md` lists upstream bugs found along the way.

## Layout

| Path                         | What                                                      |
|------------------------------|-----------------------------------------------------------|
| `flake.nix`                  | `nixosConfigurations.r36s`, `packages.*.sdImage`/`dtbs`   |
| `modules/r36s.nix`           | hardware: kernel, DTB, firmware, boot chain, SD image, gamepad merge, boot-time tuning |
| `modules/retroarch.nix`      | RetroArch package (cores, gamepad autoconfig, hotkeys), `r36s.frontend`, standalone RetroArch on tty1 |
| `modules/es-de.nix`          | ES-DE on tty1, launches games in RetroArch                |
| `configuration.nix`          | the "user" part: WiFi, SSH, users, packages               |
| `dts/rk3326-gameconsole-r36s.dts` | kernel device tree, builds on mainline `rk3326-odroid-go3.dts` |
| `drivers/panel-generic-dsi/` | out-of-tree ROCKNIX panel driver for the built-in display |
| `bootloader/`                | idbloader/U-Boot/trust blobs, `boot.ini`, U-Boot's panel DTB, templates for `/boot` |
| `pkgs/`                      | boot logo, SDL2 demo, ES-DE and FreeImage (both dropped from nixpkgs) |
| `scripts/of-kmod-rules.py`   | generates the trimmed `80-drivers.rules`                  |
| `scripts/es-systems.py`      | generates ES-DE's systems list from the installed cores   |

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

## Testing the UI without pressing buttons

- Screenshot of the panel (buffers are linear BGRA):
  `sudo ffmpeg -device /dev/dri/card0 -f kmsgrab -i - -vf hwdownload,format=bgra -frames:v 1 shot.png`
  (`nix-shell -p ffmpeg-headless` on the device).
- Button presses: create a uinput clone of `/dev/input/r36s-gamepad` with
  python-evdev, named "R36S Gamepad" with bustype/vendor/product/version 0,
  so ES-DE (SDL GUID) and RetroArch (autoconfig by name) treat it like the
  real one. RetroArch only takes hotkeys from port 1: stop
  `r36s-gamepad.service` while the clone is in use, start it again after.
- `pkill -f`/`pgrep -f` over SSH match the SSH command line itself, use a
  pattern like `"[r]etroarch-with-cores"`.
- Headless core benchmarks: `retroarch-bare` with `video_driver = "null"`
  and `--max-frames`; it needs `QT_QPA_PLATFORM=offscreen`.

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
