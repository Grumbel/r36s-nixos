# TODO / handoff

## Tip

- Branch: `master` (local commits on top of `a13471c` upstream tip)
- Work: RetroArch GLSL shaders + CPU video/audio filters, Nix-store paths (dArkOS parity without `~/` copies)

## Done this session

- `pkgs/libretro-shaders-glsl`: full `libretro/glsl-shaders` + Sharp-Shimmerless under `shaders_glsl/`
- `pkgs/libretro-shaders-glsl/minimal.nix`: nearest/bilinear, scanlines, handheld, interpolation, pixel-art-scaling, Sharp-Shimmerless (~15M vs ~39M)
- `pkgs/libretro-video-filters`, `pkgs/libretro-audio-filters`: built from `retroarch-bare.src`
- `modules/retroarch.nix`:
  - `r36s.retroarch.shaders = "full" | "minimal" | "none"` (default `"full"`)
  - `r36s.retroarch.filters` (default `true`)
  - settings: `video_shader_dir`, `video_filter_dir`, `audio_filter_dir` → store paths
- README + AGENTS layout note

## Not done / for the device

- No full system rebuild or on-device shader load test here (hand off the bundle)
- Filters are compiled for the host of the build; the SD image aarch64 build will produce aarch64 `.so`s
- Optional later: default preset via `video_shader` / per-core auto-shader; slang via librashader

## Next bundle base

- Original base for this work line: `a13471cb705a1fda6f029dc0e2a48039c7ba21fa` (short `a13471c`)
