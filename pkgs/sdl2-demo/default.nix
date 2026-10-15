{
  stdenv,
  pkg-config,
  SDL2,
}:

stdenv.mkDerivation {
  pname = "sdl2-demo";
  version = "0.1";

  src = ./.;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ SDL2 ];

  buildPhase = ''
    $CC -O2 -Wall -o sdl2-demo sdl2-demo.c $(pkg-config --cflags --libs sdl2) -lm
  '';

  installPhase = ''
    install -Dm755 sdl2-demo $out/bin/sdl2-demo
  '';

  meta.mainProgram = "sdl2-demo";
}
