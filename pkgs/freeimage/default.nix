# FreeImage, as removed from nixpkgs in 2025-10 for its unfixed CVEs.
# ES-DE still needs it. Taken from nixos-25.05 (pkgs/by-name/fr/freeimage)
# with the Darwin parts dropped; the patches are from there too.
{
  lib,
  stdenv,
  fetchsvn,
  libtiff,
  libpng,
  zlib,
  libwebp,
  libjpeg,
  pkg-config,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "freeimage";
  version = "3.18.0-unstable-2024-04-18";

  src = fetchsvn {
    url = "svn://svn.code.sf.net/p/freeimage/svn/";
    rev = "1911";
    hash = "sha256-JznVZUYAbsN4FplnuXxCd/ITBhH7bfGKWXep2A6mius=";
  };

  sourceRoot = "${finalAttrs.src.name}/FreeImage/trunk";

  # Ensure that the bundled libraries are not used at all
  prePatch = ''
    rm -rf Source/Lib* Source/OpenEXR Source/ZLib
  '';

  # Tell patch to work with trailing carriage returns
  patchFlags = [
    "-p1"
    "--binary"
  ];

  patches = [
    ./unbundle.diff
    ./CVE-2020-24292.patch
    ./CVE-2020-24293.patch
    ./CVE-2020-24295.patch
    ./CVE-2021-33367.patch
    ./CVE-2021-40263.patch
    ./CVE-2021-40266.patch
    ./CVE-2023-47995.patch
    ./CVE-2023-47997.patch
  ];

  # The EXR, TIFF and G3 plugins no longer build against OpenEXR 3 and
  # libtiff 4.7, and none of EXR, TIFF, G3 (fax), RAW, JPEG XR and JPEG 2000
  # are needed by ES-DE. Replace them with stubs that only register the format name:
  # plugins are numbered in registration order and the FIF_* constants
  # depend on that, so they can't simply be left out. A plugin without
  # validate/load functions never matches a file. Fewer parsers also means
  # less of FreeImage's unfixed CVEs.
  postPatch = ''
    for p in EXR G3 RAW JXR J2K JP2 TIFF; do
      cat > Source/FreeImage/Plugin$p.cpp <<EOF
    #include "FreeImage.h"
    #include "Utilities.h"
    static const char * DLL_CALLCONV Format() { return "$p"; }
    void DLL_CALLCONV Init$p(Plugin *plugin, int format_id) { plugin->format_proc = Format; }
    EOF
    done
    echo > Source/FreeImage/J2KHelper.cpp

    # The lossless JPEG transforms need libjpeg-turbo's transupp, which
    # nixpkgs no longer exports (libjpeg.dev_private is gone). ES-DE
    # doesn't use them, make them fail.
    cat > Source/FreeImageToolkit/JPEGTransform.cpp <<EOF
    #include "FreeImage.h"
    #define FAIL { return FALSE; }
    BOOL DLL_CALLCONV FreeImage_JPEGTransform(const char *, const char *, FREE_IMAGE_JPEG_OPERATION, BOOL) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGTransformU(const wchar_t *, const wchar_t *, FREE_IMAGE_JPEG_OPERATION, BOOL) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGCrop(const char *, const char *, int, int, int, int) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGCropU(const wchar_t *, const wchar_t *, int, int, int, int) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGTransformFromHandle(FreeImageIO *, fi_handle, FreeImageIO *, fi_handle, FREE_IMAGE_JPEG_OPERATION, int *, int *, int *, int *, BOOL) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGTransformCombined(const char *, const char *, FREE_IMAGE_JPEG_OPERATION, int *, int *, int *, int *, BOOL) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGTransformCombinedU(const wchar_t *, const wchar_t *, FREE_IMAGE_JPEG_OPERATION, int *, int *, int *, int *, BOOL) FAIL
    BOOL DLL_CALLCONV FreeImage_JPEGTransformCombinedFromMemory(FIMEMORY *, FIMEMORY *, FREE_IMAGE_JPEG_OPERATION, int *, int *, int *, int *, BOOL) FAIL
    EOF

    substituteInPlace Makefile.fip Makefile.gnu \
      --replace-fail "pkg-config" "$PKG_CONFIG" \
      --replace-fail "OpenEXR libopenjp2 libraw " "" \
      --replace-fail " libjxr" ""
  '';

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libtiff
    libtiff.dev_private
    libpng
    zlib
    libwebp
    libjpeg
  ];

  postBuild = ''
    make -f Makefile.fip
  '';

  INCDIR = "${placeholder "out"}/include";
  INSTALLDIR = "${placeholder "out"}/lib";

  preInstall = ''
    mkdir -p $INCDIR $INSTALLDIR
  '';

  postInstall = ''
    make -f Makefile.fip install
  '';

  enableParallelBuilding = true;

  meta = {
    description = "Open Source library for accessing popular graphics image file formats";
    homepage = "http://freeimage.sourceforge.net/";
    license = lib.licenses.gpl2Plus;
    # The ones fixed by the patches above are left out
    knownVulnerabilities = [
      "CVE-2024-31570"
      "CVE-2024-28584"
      "CVE-2024-28583"
      "CVE-2024-28582"
      "CVE-2024-28581"
      "CVE-2024-28580"
      "CVE-2024-28579"
      "CVE-2024-28578"
      "CVE-2024-28577"
      "CVE-2024-28576"
      "CVE-2024-28575"
      "CVE-2024-28574"
      "CVE-2024-28573"
      "CVE-2024-28572"
      "CVE-2024-28571"
      "CVE-2024-28570"
      "CVE-2024-28569"
      "CVE-2024-28568"
      "CVE-2024-28567"
      "CVE-2024-28566"
      "CVE-2024-28565"
      "CVE-2024-28564"
      "CVE-2024-28563"
      "CVE-2024-28562"
      "CVE-2024-9029"
      "CVE-2023-47996"
      "CVE-2023-47994"
      "CVE-2023-47993"
      "CVE-2023-47992"
      "CVE-2021-40265"
      "CVE-2021-40264"
      "CVE-2021-40262"
      "CVE-2020-24294"
      "CVE-2020-21426"
      "CVE-2019-12214"
      "CVE-2019-12212"
    ];
    platforms = lib.platforms.linux;
  };
})
