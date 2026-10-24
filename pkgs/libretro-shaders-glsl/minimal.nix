# Cut-down GLSL shader set for the R36S: nearest/bilinear, scanlines, handheld
# LCD/GB, sharp bilinear-style interpolation, and Sharp-Shimmerless. Omits heavy
# multipass CRT/NTSC/upscalers that cost more than they are worth on Mali-G31.
{
  lib,
  stdenvNoCC,
  libretro-shaders-glsl,
}:

stdenvNoCC.mkDerivation {
  pname = "libretro-shaders-glsl-minimal";
  version = libretro-shaders-glsl.version;

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Top-level presets and directories worth keeping on a small LCD handheld.
  keep = [
    "nearest.glslp"
    "bilinear.glslp"
    "scanlines"
    "handheld"
    "interpolation"
    "pixel-art-scaling"
    "Sharp-Shimmerless"
  ];

  installPhase = ''
    src=${libretro-shaders-glsl}/share/libretro/shaders/shaders_glsl
    dst=$out/share/libretro/shaders/shaders_glsl
    mkdir -p "$dst"
    for name in $keep; do
      if [ -e "$src/$name" ]; then
        cp -a "$src/$name" "$dst/"
      fi
    done
  '';

  meta = {
    description = "Minimal GLSL shader set for RetroArch on handhelds";
    homepage = "https://github.com/libretro/glsl-shaders";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
