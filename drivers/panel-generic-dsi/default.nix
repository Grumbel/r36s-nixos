# Generic MIPI-DSI panel driver from ROCKNIX, the panel (init sequence,
# timings, ...) is described in the device tree via `panel_description`.
#
# Source: https://github.com/ROCKNIX/distribution/blob/3ab675ddbd5c2bdc1ebbc706961b3418e937780f/projects/ROCKNIX/packages/linux-drivers/generic-dsi/sources/panel-generic-dsi.c
{ stdenv, kernel }:

stdenv.mkDerivation {
  pname = "panel-generic-dsi";
  version = "0-unstable-${kernel.version}";

  src = ./.;

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernel.commonMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
  ];
  buildFlags = [ "modules" ];

  installPhase = ''
    install -Dm644 panel-generic-dsi.ko $out/lib/modules/${kernel.modDirVersion}/extra/panel-generic-dsi.ko
  '';
}
