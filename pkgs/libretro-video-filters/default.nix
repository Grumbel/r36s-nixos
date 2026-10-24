# CPU video filters from RetroArch (*.so + *.filt). Used via video_filter_dir.
# Built from the same RetroArch revision as nixpkgs' retroarch-bare.
{
  lib,
  stdenv,
  retroarch-bare,
}:

stdenv.mkDerivation {
  pname = "libretro-video-filters";
  version = lib.getVersion retroarch-bare;

  inherit (retroarch-bare) src;

  # Only the filter tree is needed; skip the rest of the RetroArch configure.
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cd gfx/video_filters
    make -j$NIX_BUILD_CORES compiler=$CC
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/retroarch/filters/video
    cp -a *.so *.filt $out/lib/retroarch/filters/video/ 2>/dev/null || true
    runHook postInstall
  '';

  meta = {
    description = "CPU video filters for RetroArch";
    homepage = "https://github.com/libretro/RetroArch";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
