{
  pkgs ? import <nixpkgs> { },
}:
let
  sources = import ./npins;
  inherit (sources.fmd2) version;
  dockerVersion = "0.0.1";
  fmd2Src = sources.fmd2;
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
        cp ${./settings.json} $out/app/FMD2/userdata/settings.json
        cp -r ${fmd2Src}/lua app/FMD2/
        cp -r ./app $out/
      '';
  monitorScript = pkgs.writeShellScriptBin "monitor-changes" ''
    #!/bin/bash
    set -euo pipefail

    TRANSFER_FILE_TYPE=".cbz"
    THRESHOLD_MINUTES="10"

    monitor_changes() {
      local src_dir="$1"
      local dst_dir="$2"
      declare -A copied_files

      if [[ ! -d "$src_dir" || ! -d "$dst_dir" ]]; then
        echo "Source or destination directory does not exist."
        exit 1
      fi

      echo "Monitoring $src_dir for files ending with $TRANSFER_FILE_TYPE..."

      while true; do
        while IFS= read -r -d "" file; do
          if [[ -z ${"\${copied_files[$file]+_}"} ]]; then
            rel_parent_dir="$(basename "$(dirname "$file")")"
            target_dir="$dst_dir/$rel_parent_dir"
            mkdir -p "$target_dir"
            attempt=0
            max_attempts=10
            rsync_success=false
            while [[ $attempt -lt $max_attempts ]]; do
              rsync -a "$file" "$target_dir/" && rsync_success=true && break
              ((attempt++))
              echo "rsync failed for $file. Retry attempt $attempt of $max_attempts..."
              sleep 30
            done
            copied_files["$file"]=1
            echo "Copied: $file -> $target_dir/"
          fi
        done < <(find "$src_dir" -type f -name "*$TRANSFER_FILE_TYPE" -print0)

        find "$src_dir" -mindepth 1 -type d -cmin +"$THRESHOLD_MINUTES" -exec rm -r {} + 2>/dev/null || true

        sleep 20
      done
    }

    if [[ "$#" -ne 2 ]]; then
      echo "Usage: $0 <source_dir> <destination_dir>"
      exit 1
    fi

    monitor_changes "$1" "$2" &
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
          websockify -D --web=/home/fmd2/.wine/drive_c/novnc 6080 0.0.0.0:5900 &
          monitor-changes /home/fmd2/.wine/drive_c/app/FMD2/downloads /downloads
          openbox-session &
          sleep 20
          cd /home/fmd2/.wine/drive_c/app/FMD2
          wine fmd.exe
        ''
      ];
    };

    fakeRootCommands = ''
      mkdir -p tmp home/fmd2/.wine/drive_c downloads home/fmd2/.config/openbox
      cp -rL ${./openbox.xml} home/fmd2/.config/openbox/rc.xml
      chown 1000:1000 downloads
      chmod +w downloads
      chmod 777 -R tmp
      cp -rL ${fmd2App}/* ./home/fmd2/.wine/drive_c
      chown 1000:1000 -R home/fmd2
      chmod ug+w -R home/fmd2
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
      monitorScript
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
      python3
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
