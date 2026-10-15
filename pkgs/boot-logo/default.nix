# Boot splash shown by U-Boot: the NixOS snowflake on a dark background.
# U-Boot wants an uncompressed 24 bit BMP in the panel's resolution.
{
  runCommand,
  imagemagick,
  librsvg,
  nixos-icons,
  dejavu_fonts,
}:

runCommand "r36s-boot-logo.bmp"
  {
    nativeBuildInputs = [
      imagemagick
      librsvg
    ];
  }
  ''
    rsvg-convert -w 240 -h 240 --keep-aspect-ratio \
      ${nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg -o flake.png
    magick -size 640x480 xc:'#121826' \
      flake.png -gravity center -geometry +0-40 -composite \
      -font ${dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf \
      -pointsize 44 -fill '#e6ecf5' -gravity center -annotate +0+130 'NixOS' \
      -type TrueColor -alpha off BMP3:$out
  ''
