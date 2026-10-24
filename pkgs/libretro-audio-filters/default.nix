# Audio DSP filters from RetroArch (*.so + *.dsp). Used via audio_filter_dir.
{
  lib,
  stdenv,
  retroarch-bare,
}:

stdenv.mkDerivation {
  pname = "libretro-audio-filters";
  version = lib.getVersion retroarch-bare;

  inherit (retroarch-bare) src;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cd libretro-common/audio/dsp_filters
    make -j$NIX_BUILD_CORES compiler=$CC
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/retroarch/filters/audio
    cp -a *.so *.dsp $out/lib/retroarch/filters/audio/ 2>/dev/null || true
    runHook postInstall
  '';

  meta = {
    description = "Audio DSP filters for RetroArch";
    homepage = "https://github.com/libretro/RetroArch";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
