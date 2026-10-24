# ES-DE (EmulationStation Desktop Edition) as the front end, when
# r36s.frontend = "emulationstation": started on tty1 at boot, games are
# launched in RetroArch (modules/retroarch.nix). Only systems with an
# installed core are listed, see scripts/es-systems.py.
#
# ES-DE's settings live in ~/ES-DE. They are seeded on the first start and
# can then be changed from its menu; only the ROM directory always follows
# r36s.retroarch.romDirectory.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = "nixos";
  retroarch = config.r36s.retroarch.package;

  freeimage = pkgs.callPackage ../pkgs/freeimage { };
  es-de = pkgs.callPackage ../pkgs/es-de { inherit freeimage; };

  # gpsp for GBA (~2.7x faster than mgba), and the fast Mega Drive and
  # SNES cores when the unfree cores are enabled
  preferredCores = [
    "gpsp"
    "picodrive"
    "snes9x2005_plus"
  ];

  esSystems =
    pkgs.runCommand "es-de-systems.xml" { nativeBuildInputs = [ pkgs.buildPackages.python3 ]; }
      ''
        python3 ${../scripts/es-systems.py} \
          ${es-de}/share/es-de/resources/systems/linuxarm/es_systems.xml \
          ${retroarch}/lib/retroarch/cores ${retroarch}/bin/retroarch \
          ${lib.concatStringsSep "," preferredCores} $out
      '';

  # SDL's automatic mapping of the merged gamepad names the buttons by
  # position (Xbox style): the bottom button, B on the R36S, is "a". Like a
  # Switch controller, map them by label instead, so A (right) selects,
  # B (bottom) goes back and ES-DE's "switchpro" button icons are right.
  # Button numbers are in key code order, as in the RetroArch autoconfig.
  # The GUID is derived from the device name "R36S Gamepad".
  sdlMapping = lib.concatStringsSep "," [
    "00006698523336532047616d65706100"
    "R36S Gamepad"
    "a:b1"
    "b:b0"
    "x:b2"
    "y:b3"
    "leftshoulder:b4"
    "rightshoulder:b5"
    "lefttrigger:b6"
    "righttrigger:b7"
    "back:b8"
    "start:b9"
    "guide:b10"
    "leftstick:b11"
    "rightstick:b12"
    "dpup:b13"
    "dpdown:b14"
    "dpleft:b15"
    "dpright:b16"
    "leftx:a0"
    "lefty:a1"
    "rightx:a2"
    "righty:a3"
    "platform:Linux"
  ];

  defaultSettings = pkgs.writeText "es_settings.xml" ''
    <?xml version="1.0"?>
    <bool name="ShowQuitMenu" value="true" />
    <!-- Nintendo button labels, see sdlMapping -->
    <string name="InputControllerType" value="switchpro" />
  '';
in
{
  config = lib.mkIf (config.r36s.frontend == "emulationstation") {
    # Has around 40 open CVEs in its image parsers. ES-DE only reads the
    # themes and game media, and the plugins for the exotic formats are
    # stubbed out, see pkgs/freeimage.
    nixpkgs.config.permittedInsecurePackages = [ freeimage.name ];

    environment.systemPackages = [ es-de ];

    # ES-DE's Quit menu powers off, reboots and suspends as the logged in
    # user (`shutdown --poweroff now`, `systemctl suspend`). With polkit,
    # logind allows that for the active local session on tty1.
    security.polkit.enable = true;

    systemd.services.es-de = {
      description = "ES-DE";
      wantedBy = [ "multi-user.target" ];
      wants = [ "r36s-gamepad.service" ];
      after = [
        "systemd-user-sessions.service"
        "r36s-gamepad.service"
        "sound.target"
      ];
      conflicts = [ "getty@tty1.service" ];
      # Don't kill a running game on nixos-rebuild switch, changes apply on
      # the next start
      restartIfChanged = false;
      environment.SDL_GAMECONTROLLERCONFIG = sdlMapping;

      serviceConfig = {
        User = user;
        # A logind session on tty1, so ES-DE and RetroArch may become DRM
        # master
        PAMName = "login";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        StandardInput = "tty";
        StandardOutput = "journal";
        StandardError = "journal";
        UtmpIdentifier = "tty1";
        UtmpMode = "user";

        ExecStartPre = pkgs.writeShellScript "es-de-setup" ''
          set -eu
          cd "$HOME"
          mkdir -p ES-DE/settings ES-DE/custom_systems
          ln -sfn ${esSystems} ES-DE/custom_systems/es_systems.xml
          settings=ES-DE/settings/es_settings.xml
          if [ ! -e $settings ]; then
            install -m 644 ${defaultSettings} $settings
          fi
          rom='<string name="ROMDirectory" value="${config.r36s.retroarch.romDirectory}" />'
          if grep -q 'name="ROMDirectory"' $settings; then
            sed -i "s|<string name=\"ROMDirectory\".*|$rom|" $settings
          else
            echo "$rom" >> $settings
          fi
        '';
        ExecStart = lib.getExe es-de;
        # "Quit ES-DE" in its menu just starts it again, there is nothing
        # else on the display
        Restart = "always";
        RestartSec = 1;
      };
    };
  };
}
