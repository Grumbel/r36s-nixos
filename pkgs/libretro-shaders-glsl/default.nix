# GLSL shaders for RetroArch (GL driver). Matches dArkOS: full libretro/glsl-shaders
# tree plus Sharp-Shimmerless nested under shaders_glsl/.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "libretro-shaders-glsl";
  version = "0-unstable-2026-10-23";

  src = fetchFromGitHub {
    owner = "libretro";
    repo = "glsl-shaders";
    rev = "cba01a48b0974a1232bea68d999a7c21bc4c233e";
    hash = "sha256-yOWcGx+jl8g7jEVJJfXtV5dBWMLy29GykA+jTOQ2inQ=";
  };

  # Handheld-friendly sharp scaling preset pack (GLSL half only), same as dArkOS.
  sharpShimmerless = fetchFromGitHub {
    owner = "Woohyun-Kang";
    repo = "Sharp-Shimmerless-Shader";
    rev = "2a74e7af599335c2ce5e493f823a757925c80db3";
    hash = "sha256-dZptdO/xSVHoyyS5vc9MZOQ4bjzf/3heRWAtUvAP+00=";
  };

  dontConfigure = true;
  dontBuild = true;

  # Upstream Makefile: PREFIX/share/libretro/shaders/shaders_glsl
  installFlags = [ "PREFIX=${placeholder "out"}" ];

  postInstall = ''
    ss="$out/share/libretro/shaders/shaders_glsl/Sharp-Shimmerless"
    mkdir -p "$ss"
    # Repo has shaders_glsl/ and shaders_slang/; only GLSL is useful with video_driver=gl
    if [ -d "$sharpShimmerless/shaders_glsl" ]; then
      cp -a "$sharpShimmerless/shaders_glsl/." "$ss/"
    else
      cp -a "$sharpShimmerless/." "$ss/"
      rm -rf "$ss/shaders_slang" "$ss/.git" "$ss/README.md" 2>/dev/null || true
    fi
  '';

  meta = {
    description = "GLSL shaders for RetroArch (full libretro set + Sharp-Shimmerless)";
    homepage = "https://github.com/libretro/glsl-shaders";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.all;
  };
}
