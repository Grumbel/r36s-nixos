# ES-DE (EmulationStation Desktop Edition), removed from nixpkgs together
# with FreeImage. Based on the nixos-25.05 package, updated and built for
# OpenGL ES (panfrost) and KMS.
{
  lib,
  stdenv,
  fetchzip,
  cmake,
  pkg-config,
  alsa-lib,
  bluez,
  curl,
  ffmpeg,
  freeimage,
  freetype,
  glib,
  gettext,
  harfbuzz,
  icu,
  libgit2,
  poppler,
  pugixml,
  SDL2,
  libGL,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "es-de";
  version = "3.5.0";

  src = fetchzip {
    url = "https://gitlab.com/es-de/emulationstation-de/-/archive/v${finalAttrs.version}/emulationstation-de-v${finalAttrs.version}.tar.gz";
    hash = "sha256-MFCLE8RnpvSAYY4UhJ+uwdIlhlyJsiLjSUUAJrNgd1c=";
  };

  postPatch = ''
    # ldd based detection doesn't work in the sandbox
    substituteInPlace CMake/Packages/FindPoppler.cmake \
      --replace-fail 'GET_PREREQUISITES("''${POPPLER_LIBRARY}" POPPLER_PREREQS 1 0 "" "")' ""
  '';

  nativeBuildInputs = [
    cmake
    gettext # msgfmt
    pkg-config
  ];

  buildInputs = [
    alsa-lib
    bluez
    curl
    ffmpeg
    freeimage
    freetype
    glib
    harfbuzz
    icu
    libgit2
    # For es-pdf-converter, the game manual viewer
    poppler
    pugixml
    SDL2
    libGL
  ];

  cmakeFlags = [
    (lib.cmakeBool "APPLICATION_UPDATER" false)
    # Mali-G31 with panfrost
    (lib.cmakeBool "GL" false)
    (lib.cmakeBool "GLES" true)
    # Close the window and give up DRM master while a game runs, so the
    # emulator can take over the display
    (lib.cmakeBool "DEINIT_ON_LAUNCH" true)
  ];

  meta = {
    description = "Frontend for browsing and launching games from your multi-platform collection";
    homepage = "https://es-de.org";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "es-de";
  };
})
