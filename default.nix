{
  pkgs ? import <nixpkgs> { },
  dockerVersion ? "0.0.0",
}:
let
  sources = import ./npins;
  inherit (sources.fmd2) version;
  fmd2LatestSrc = sources.fmd2-latest;
  fmd2Url = "https://github.com/dazedcat19/FMD2/releases/download/${version}/fmd_${version}_x86_64-win64.7z";
  fmd2Archive = pkgs.fetchurl {
    url = fmd2Url;
    sha256 = "sha256-3TUwDuIu8E/VZSO6JB/ZcvraXHgO2LatTQb9g78jFDQ=";
  };
  fmd2App =
    pkgs.runCommand "fmd2App"
      {
        buildInputs = [ pkgs.p7zip ];
      }
      ''
        mkdir -p $out/app/FMD2 $out/app/FMD2/userdata $out/app/FMD2/downloads $out/app/FMD2/data $out/wine
        cp -r ${pkgs.novnc}/share/webapps/novnc ./novnc
        chmod +w ./novnc -R
        cp ${pkgs.novnc}/share/webapps/novnc/vnc_lite.html ./novnc/index.html
        cp -r ./novnc $out/
        7z x ${fmd2Archive} -oapp/FMD2 -y
        chmod +w ./app -R
        cp ${./settings.json} $out/app/FMD2/settings.json
        cp -r ${fmd2LatestSrc}/lua app/FMD2/
        cp -r ./app $out/
      '';
  buildOciStream = pkgs.dockerTools.streamLayeredImage {
    name = "zot.bealv.io/public/fmd2-nix";
    tag = "v${version}-v${dockerVersion}";
    created = "now";

    config = {
      User = "1000:1000";
      ExposedPorts = {
        "6080/tcp" = { };
      };
      Env = [
        "WINEPREFIX=/home/fmd2/.wine"
        "DISPLAY=:1"
        "WINEDLLOVERRIDES=mscoree,mshtml="
        "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
        "FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts/"
      ];
      Cmd = [
        "/bin/bash"
        "-c"
        ''
          Xvfb :1 -screen 0 1920x1080x16 &  # Start virtual display
          x11vnc -display :1 -noipv6 -reopen -forever -repeat -loop -rfbport 5900 -noxdamage &
          websockify -D --web=/novnc 6080 0.0.0.0:5900 &
          openbox-session &
          sleep 20
          cd /app/FMD2
          if [ ! -f /app/FMD2/userdata/settings.json ]; then
            cp /app/FMD2/settings.json /app/FMD2/userdata/settings.json
          fi
          sudo chown 1000:1000 -R /home/fmd2/.wine
          sudo chmod +w -R /home/fmd2/.wine
          sudo chown 1000:1000 -R /app
          sudo chmod +w -R /app
          wine fmd.exe
        ''
      ];
    };

    fakeRootCommands = ''
      mkdir -p tmp home/fmd2/.wine/drive_c home/fmd2/.config/openbox app/FMD2
      cp -rL ${./openbox.xml} home/fmd2/.config/openbox/rc.xml
      chmod 777 -R tmp
      cp -rL ${fmd2App}/* ./
      chown 1000:1000 -R home/fmd2
      chown 1000:1000 -R home/fmd2/.wine
      chown 0:0 usr/bin/sudo && chmod 4755 usr/bin/sudo
      chmod ug+w -R home/fmd2
      chown 1000:1000 -R app
      chmod ug+w -R app
    '';

    extraCommands = ''
      mkdir -p usr/bin
      cp -L ${pkgs.sudo}/bin/sudo usr/bin
    '';

    contents = with pkgs; [
      (pkgs.dockerTools.fakeNss.override {
        extraPasswdLines = [
          "fmd2:x:1000:1000:Build user:/home/fmd2:/bin/bash"
        ];
        extraGroupLines = [
          "fmd2:!:1000:"
        ];
      })
      inotify-tools
      rsync
      findutils
      openbox
      bashInteractive
      dockerTools.binSh
      dockerTools.usrBinEnv
      dockerTools.caCertificates
      cacert.out
      openssl
      coreutils
      wineWow64Packages.stable
      winePackages.stable
      wine64
      winetricks
      (pkgs.python3.withPackages (
        ps: with ps; [
          websockify
          requests
        ]
      ))
      (pkgs.writeTextDir "etc/sudoers" ''
        root     ALL=(ALL:ALL)    SETENV: ALL
        %wheel  ALL=(ALL:ALL)    NOPASSWD:SETENV: ALL
        fmd2 ALL=(ALL) NOPASSWD:ALL
        Defaults:root,%wheel env_keep+=TERMINFO_DIRS
        Defaults:root,%wheel env_keep+=TERMINFO
      '')
      (pkgs.runCommand "config-sudo" { } ''
        mkdir -p $out/etc/pam.d/backup
        cat > $out/etc/pam.d/sudo <<EOF
        #%PAM-1.0
        auth        sufficient  pam_rootok.so
        auth        sufficient  pam_permit.so
        account     sufficient  pam_permit.so
        account     required    pam_warn.so
        session     required    pam_permit.so
        password    sufficient  pam_permit.so
        EOF
        cat > $out/etc/pam.d/su <<EOF
        #%PAM-1.0
        auth        sufficient  pam_rootok.so
        auth        sufficient  pam_permit.so
        account     sufficient  pam_permit.so
        account     required    pam_warn.so
        session     required    pam_permit.so
        password    sufficient  pam_permit.so
        EOF
        cat > $out/etc/pam.d/system-auth <<EOF
        #%PAM-1.0
        auth        required      pam_env.so
        auth        sufficient    pam_rootok.so
        auth        sufficient    pam_permit.so
        auth        sufficient    pam_unix.so try_first_pass nullok
        auth        required      pam_deny.so
        account     sufficient    pam_permit.so
        account     required      pam_unix.so
        password    sufficient    pam_permit.so
        password    required      pam_unix.so
        session     required      pam_unix.so
        session     optional      pam_permit.so
        EOF
        cat > $out/etc/pam.d/login <<EOF
        #%PAM-1.0
        auth        required      pam_env.so
        auth        sufficient    pam_rootok.so
        auth        sufficient    pam_permit.so
        auth        sufficient    pam_unix.so try_first_pass nullok
        auth        required      pam_deny.so
        account     sufficient    pam_permit.so
        account     required      pam_unix.so
        password    sufficient    pam_permit.so
        password    required      pam_unix.so
        session     required      pam_unix.so
        session     optional      pam_permit.so
        EOF
        cat >> $out/etc/sudoers <<EOF
        root     ALL=(ALL:ALL)    NOPASSWD:SETENV: ALL
        %wheel  ALL=(ALL:ALL)    NOPASSWD:SETENV: ALL
        EOF
      '')
      python312Packages.websockify
      python312Packages.requests
      x11vnc
      openbox
      xorg.xvfb
      novnc
    ];
  };
in
{
  inherit buildOciStream;
}
