# ES-DE (EmulationStation Desktop Edition) as the front end, when
# r36s.frontend = "emulationstation": started on tty1 at boot, games are
# launched in RetroArch (modules/retroarch.nix). Only systems with an
# installed core are listed, see scripts/es-systems.py.
#
# Native games can be added to the "Ports" system with r36s.es-de.ports.
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

  ports = config.r36s.es-de.ports;

  # One launcher script per port, ES-DE lists them by file name. Select +
  # Start quits the game, like gptokeyb does for PortMaster ports: evsieve
  # watches the gamepad (without grabbing it) next to the game, and kills
  # it if it doesn't quit within 3 s (Kurvenrausch takes ~20 s). ES-DE
  # doesn't keep the output of games, so it goes to the journal.
  portLaunchers = pkgs.runCommand "es-de-ports" { } (
    ''
      mkdir $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (_: port: ''
        cp ${pkgs.writeShellScript "port" ''
          # Output to the journal: journalctl -t ${lib.escapeShellArg port.name}
          ${port.command} > >(${config.systemd.package}/bin/systemd-cat -t ${lib.escapeShellArg port.name}) 2>&1 &
          game=$!
          ${pkgs.evsieve}/bin/evsieve --input /dev/input/r36s-gamepad \
            --hook btn:select btn:start "exec-shell=kill $game; sleep 3; kill -9 $game" &
          watcher=$!
          wait $game
          rc=$?
          kill $watcher
          exit $rc
        ''} $out/${lib.escapeShellArg "${port.name}.sh"}
      '') ports
    )
  );

  portsSystem = pkgs.writeText "es-de-ports.xml" ''
    <systemList>
      <system>
        <name>ports</name>
        <fullname>Ports</fullname>
        <path>${portLaunchers}</path>
        <extension>.sh</extension>
        <command label="Native">${pkgs.bash}/bin/bash %ROM%</command>
        <platform>pc</platform>
        <theme>ports</theme>
      </system>
    </systemList>
  '';

  esSystems =
    pkgs.runCommand "es-de-systems.xml" { nativeBuildInputs = [ pkgs.buildPackages.python3 ]; }
      ''
        python3 ${../scripts/es-systems.py} \
          ${es-de}/share/es-de/resources/systems/linuxarm/es_systems.xml \
          ${retroarch}/lib/retroarch/cores ${retroarch}/bin/retroarch \
          ${lib.concatStringsSep "," preferredCores} $out \
          ${lib.optionalString (ports != { }) portsSystem}
      '';

  # ES-DE looks for game media by file name
  portScreenshots = lib.filterAttrs (_: port: port.screenshot != null) ports;

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
  options.r36s.es-de.ports = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Name shown in ES-DE.";
            };
            command = lib.mkOption {
              type = lib.types.str;
              example = lib.literalExpression ''"''${pkgs.supertux}/bin/supertux2 --fullscreen"'';
              description = ''
                Command that starts the game. It runs in the background of
                the launcher script, so it should be the game itself and not
                a wrapper that forks.
              '';
            };
            screenshot = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Image shown for the game in ES-DE.";
            };
          };
        }
      )
    );
    default = { };
    description = ''
      Native games listed in ES-DE's "Ports" system. They get the gamepad
      through SDL's game controller API with the R36S mapping, Select +
      Start quits them.
    '';
  };

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
          ${lib.optionalString (portScreenshots != { }) ''
            mkdir -p ES-DE/downloaded_media/ports/screenshots
            ${lib.concatStrings (
              lib.mapAttrsToList (_: port: ''
                ln -sfn ${port.screenshot} ${lib.escapeShellArg "ES-DE/downloaded_media/ports/screenshots/${port.name}.png"}
              '') portScreenshots
            )}''}
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
