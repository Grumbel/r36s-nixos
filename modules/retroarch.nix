# RetroArch as the front end: started on tty1 at boot, controlled with the
# gamepad only. Quitting RetroArch from its menu powers the device off.
#
#   Select + X       open the menu while a game is running
#   Select + Start   close the game and go back to the menu
#   Main Menu -> Quit RetroArch shuts the device down
{
  config,
  lib,
  pkgs,
  ...
}:

let
  user = "nixos";

  # Button and axis numbers of the merged "R36S Gamepad" as seen by the
  # udev joypad driver: buttons are numbered in key code order, the
  # D-pad comes last as it uses BTN_DPAD_* codes.
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
    input_enable_hotkey_btn = "8"
    input_menu_toggle_btn = "2"
    input_close_content_btn = "9"
  '';

  retroarch = pkgs.wrapRetroArch {
    # Free cores that are in the binary cache
    cores = with pkgs.libretro; [
      beetle-pce-fast
      fceumm
      gambatte
      mgba
      pcsx-rearmed
      stella
    ];

    settings = {
      video_driver = "gl";
      video_context_driver = "kms";
      video_fullscreen = "true";
      video_vsync = "true";
      audio_driver = "alsa";
      input_driver = "udev";
      input_joypad_driver = "udev";
      input_autodetect_enable = "true";
      joypad_autoconfig_dir = "${autoconfig}";
      menu_driver = "rgui";
      # The Qt desktop UI aborts without X11/Wayland
      ui_companion_enable = "false";
      ui_companion_start_on_boot = "false";
      desktop_menu_enable = "false";
      # Quitting powers the device off, only allow it from the menu
      input_exit_emulator_btn = "nul";
      rgui_browser_directory = "/home/${user}/roms";
      # Neither works on a read-only Nix store
      menu_show_core_updater = "false";
      menu_show_online_updater = "false";
    };
  };
in
{
  environment.systemPackages = [ retroarch ];

  # tty1 belongs to RetroArch, a getty there would stop it
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  systemd.tmpfiles.rules = [ "d /home/${user}/roms 0755 ${user} users -" ];

  systemd.services.retroarch = {
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
}
