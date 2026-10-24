# RetroArch with the cores, and RetroArch as the front end when
# r36s.frontend = "retroarch": started on tty1 at boot, controlled with the
# gamepad only. Quitting RetroArch from its menu powers the device off.
#
#   Select + X       open the menu while a game is running
#   Select + Start   close the game and go back to the menu (with ES-DE as
#                    front end: quit RetroArch, back to ES-DE)
#   Main Menu -> Quit RetroArch shuts the device down (ES-DE: back to ES-DE)
#
# See README.md for the other hotkeys.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.r36s.retroarch;
  standalone = config.r36s.frontend == "retroarch";

  user = "nixos";

  # Free cores in the binary cache that run full speed on the RK3326.
  # gpsp is the GBA default: ~250 fps on Another World, Doom2D and Celeste
  # Classic (core only, 1296 MHz), mgba only manages ~85 fps, vba-next ~130.
  defaultCores = with pkgs.libretro; [
    atari800
    beetle-ngp
    beetle-pce-fast
    beetle-wswan
    bluemsx
    dosbox-pure
    fceumm
    gambatte
    gpsp
    handy
    mgba
    pcsx-rearmed
    prboom
    prosystem
    stella
    tic80
    vecx
  ];

  # Mega Drive and SNES cores are all unfree in nixpkgs, so they are not
  # in the binary cache and get built locally.
  unfreeCores = with pkgs.libretro; [
    genesis-plus-gx
    picodrive
    snes9x2005-plus
    snes9x2010
  ];

  # Names as seen by allowUnfreePredicate. Spelled out, as deriving them
  # from the packages above would make pkgs depend on itself.
  unfreeCoreNames = [
    "libretro-genesis-plus-gx"
    "libretro-picodrive"
    "libretro-snes9x2005-plus"
    "libretro-snes9x2010"
  ];

  # Button and axis numbers of the merged "R36S Gamepad" as seen by the
  # udev joypad driver: buttons are numbered in key code order, the
  # D-pad comes last as it uses BTN_DPAD_* codes. FN (BTN_MODE) is 10.
  autoconfig = pkgs.writeTextDir "R36S Gamepad.cfg" ''
    input_driver = "udev"
    input_device = "R36S Gamepad"
    input_b_btn = "0"
    input_a_btn = "1"
    input_x_btn = "2"
    input_y_btn = "3"
    input_l_btn = "4"
    input_r_btn = "5"
    input_l2_btn = "6"
    input_r2_btn = "7"
    input_select_btn = "8"
    input_start_btn = "9"
    input_l3_btn = "11"
    input_r3_btn = "12"
    input_up_btn = "13"
    input_down_btn = "14"
    input_left_btn = "15"
    input_right_btn = "16"
    input_l_x_plus_axis = "+0"
    input_l_x_minus_axis = "-0"
    input_l_y_plus_axis = "+1"
    input_l_y_minus_axis = "-1"
    input_r_x_plus_axis = "+2"
    input_r_x_minus_axis = "-2"
    input_r_y_plus_axis = "+3"
    input_r_y_minus_axis = "-3"
    # Hotkeys, all with Select held
    input_enable_hotkey_btn = "8"
    input_menu_toggle_btn = "2"
    ${if standalone then ''input_close_content_btn = "9"'' else ''input_exit_emulator_btn = "9"''}
    input_save_state_btn = "5"
    input_load_state_btn = "4"
    input_state_slot_decrease_btn = "15"
    input_state_slot_increase_btn = "16"
    input_toggle_fast_forward_btn = "7"
    input_pause_toggle_btn = "1"
    input_screenshot_btn = "3"
  '';

  retroarch = pkgs.wrapRetroArch {
    cores = cfg.cores;

    settings = {
      video_driver = "gl";
      video_context_driver = "kms";
      video_fullscreen = "true";
      video_vsync = "true";
      # Both from dArkOS. mgba on Another World: 3000 frames took 54.3 s
      # with neither, 53.8 s (= 50 s at 60 fps + startup) with both.
      video_threaded = "true";
      audio_driver = "alsathread";
      input_driver = "udev";
      input_joypad_driver = "udev";
      input_autodetect_enable = "true";
      joypad_autoconfig_dir = "${autoconfig}";
      menu_driver = "rgui";
      # The Qt desktop UI aborts without X11/Wayland
      ui_companion_enable = "false";
      ui_companion_start_on_boot = "false";
      desktop_menu_enable = "false";
      rgui_browser_directory = cfg.romDirectory;
      # Neither works on a read-only Nix store
      menu_show_core_updater = "false";
      menu_show_online_updater = "false";
    }
    // lib.optionalAttrs (!standalone) {
      # Select + Start goes back to ES-DE right away, not only on the
      # second press
      quit_press_twice = "false";
    }
    // lib.optionalAttrs standalone {
      # Quitting powers the device off, only allow it from the menu
      input_exit_emulator_btn = "nul";
    }
    // cfg.settings;
  };
in
{
  options.r36s.frontend = lib.mkOption {
    type = lib.types.enum [
      "emulationstation"
      "retroarch"
    ];
    default = "emulationstation";
    description = ''
      What starts on the display at boot: ES-DE, which launches games in
      RetroArch, or RetroArch on its own.
    '';
  };

  options.r36s.retroarch = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = retroarch;
      description = "RetroArch with the configured cores and settings.";
    };

    cores = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = defaultCores ++ lib.optionals cfg.unfreeCores unfreeCores;
      defaultText = lib.literalMD "free cores that run well on the R36S, plus the unfree ones if `unfreeCores` is set";
      description = "libretro cores to install.";
    };

    unfreeCores = lib.mkEnableOption ''
      the unfree Mega Drive and SNES cores (picodrive, genesis-plus-gx,
      snes9x2005-plus, snes9x2010). They are not in the binary cache and
      are built locally'';

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        savefiles_in_content_dir = "true";
      };
      description = "Extra RetroArch settings, they override the ones set here.";
    };

    romDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/roms";
      description = ''
        Where ROMs are looked for. Created if it doesn't exist, mount a
        partition or second SD card there to keep ROMs elsewhere.
      '';
    };
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = lib.mkIf cfg.unfreeCores (
      pkg: builtins.elem (lib.getName pkg) unfreeCoreNames
    );

    environment.systemPackages = [ retroarch ];

    # tty1 belongs to the front end, a getty there would stop it
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    systemd.tmpfiles.rules = [ "d ${cfg.romDirectory} 0755 ${user} users -" ];

    systemd.services.retroarch = lib.mkIf standalone {
      description = "RetroArch";
      wantedBy = [ "multi-user.target" ];
      wants = [ "r36s-gamepad.service" ];
      after = [
        "systemd-user-sessions.service"
        "r36s-gamepad.service"
        "sound.target"
      ];
      conflicts = [ "getty@tty1.service" ];
      # Like services.cage: don't kill a running game on nixos-rebuild switch,
      # changes apply on the next start
      restartIfChanged = false;

      serviceConfig = {
        User = user;
        # A logind session on tty1, so RetroArch may become DRM master
        PAMName = "login";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        StandardInput = "tty";
        StandardOutput = "journal";
        StandardError = "journal";
        UtmpIdentifier = "tty1";
        UtmpMode = "user";

        # Quitting RetroArch from its menu shuts the device down, a crash
        # restarts it. RetroArch also exits with 0 on SIGTERM, so the exit
        # status alone can't tell a menu quit from `systemctl stop`: the
        # wrapper only leaves the poweroff flag when RetroArch exited on its
        # own, not when the service is being stopped.
        RuntimeDirectory = "retroarch";
        ExecStart = pkgs.writeShellScript "retroarch-session" ''
          ${retroarch}/bin/retroarch &
          pid=$!
          trap 'kill -TERM $pid 2>/dev/null; wait $pid; exit 143' TERM INT HUP
          wait $pid
          rc=$?
          if [ $rc -eq 0 ]; then
            touch "$RUNTIME_DIRECTORY/poweroff"
          fi
          exit $rc
        '';
        Restart = "on-failure";
        RestartSec = 2;
        # The wrapper exits with 143 when the service is stopped
        SuccessExitStatus = 143;
        ExecStopPost = "+${pkgs.writeShellScript "retroarch-poweroff" ''
          if [ -e /run/retroarch/poweroff ]; then
            ${config.systemd.package}/bin/systemctl --no-block poweroff
          fi
        ''}";
      };
    };
  };
}
