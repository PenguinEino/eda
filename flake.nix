{
  description = "OpenSUSI TR-1um・sky130・gf180mcu 向けのアナログ設計環境（macOS ネイティブ、nix-eda ベース）";

  inputs = {
    # EDA ツール一式。FOSSi Foundation がビルド済みバイナリを配っている。
    # nixpkgs も nix-eda が固定しているものをそのまま使う（FOSSi のキャッシュとハッシュを一致させるため）。
    nix-eda.url = "github:fossi-foundation/nix-eda/7.20.0";

    # nix-eda の nixpkgs を指す別名（新しく取ってくるわけではない）。
    # nix develop は対話用の bash を「nixpkgs」という名前の入力から探すので、
    # これがないと別の nixpkgs（unstable）を余計にダウンロードしてしまう。
    nixpkgs.follows = "nix-eda/nixpkgs";

    # TR-1um の PDK。dev ブランチを追う（実際のコミットは flake.lock で固定される）。
    tr1um = {
      url = "github:OpenSUSI/TR-1um/dev";
      flake = false;
    };

    # ishi-kai のセットアップスクリプト。KLayout のメニューに足すマクロだけを使う。
    ishikai = {
      url = "github:ishi-kai/OpenEDA-PDK_SetupScript";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nix-eda,
      tr1um,
      ishikai,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nix-eda.inputs.nixpkgs.lib.genAttrs systems (system: f system);

      # sky130・gf180mcu の版（open_pdks のコミット）と、ciel が作る中身のハッシュ
      cielPdks = builtins.fromJSON (builtins.readFile ./pdks.json);

      mkEnv =
        system:
        let
          # nixpkgs ＋ FOSSi の EDA ツール
          pkgs = nix-eda.legacyPackages.${system};
          # 同じ nixpkgs の、FOSSi が差し替える前のもの
          nixpkgs = nix-eda.inputs.nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;

          # ngspice は nixpkgs のもの（45）。cache.nixos.org にビルド済みがある。
          # nix-eda の 47 は TR-1um の容量モデル（F_CSIO）を読めず、どこのキャッシュにもない。
          ngspice = nixpkgs.ngspice;

          # ---- PDK -------------------------------------------------------------

          # ciel（FOSSi の PDK 管理ツール）で公式のビルド済み PDK を取ってきて、
          # そのまま /nix/store に置く。中身は pdks.json のハッシュで検証される。
          mkCielPdk =
            family:
            { version, hash }:
            pkgs.runCommand "pdk-${family}-${lib.substring 0 7 version}"
              {
                nativeBuildInputs = [ nixpkgs.pdk-ciel ];
                outputHashMode = "recursive";
                outputHashAlgo = "sha256";
                outputHash = hash;
                SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              }
              ''
                export HOME="$TMPDIR"
                ciel enable --pdk-root "$out" --pdk-family ${family} ${version}
              '';

          pdks = {
            sky130 = mkCielPdk "sky130" cielPdks.sky130;
            gf180mcu = mkCielPdk "gf180mcu" cielPdks.gf180mcu;
          };

          # ---- X11（XQuartz）------------------------------------------------------

          # X11 アプリを起動する前に XQuartz を用意し、DISPLAY を返す
          eda-xserver = pkgs.writeShellApplication {
            name = "eda-xserver";
            runtimeInputs = [
              pkgs.xquartz
              pkgs.quartz-wm
              pkgs.xset
            ];
            text = builtins.readFile ./eda-xserver.sh;
          };

          # X11 アプリを「XQuartz を用意してから起動する」ラッパーで包む
          #（ngspice・netgen はバッチで使うことが多いので包まない。
          #  xschem から起動したときは DISPLAY が引き継がれる。
          #  端末から ngspice の plot を使うときは `export DISPLAY=$(eda-xserver)` してから）
          withX =
            name: exe: extraArgs:
            pkgs.writeShellScriptBin name ''
              ${extraArgs}
              DISPLAY="$(${eda-xserver}/bin/eda-xserver)" || exit 1
              export DISPLAY
              exec ${exe} "''${args[@]}" "$@"
            '';

          xschem = withX "xschem" "${pkgs.xschem}/bin/xschem" ''
            # 作業フォルダに xschemrc があればそれを、なければ PDK 付属のものを毎回直接読む
            args=()
            case " $* " in
              *" --rcfile"*) ;;
              *) [ -f ./xschemrc ] || args=(--rcfile "$PDK_ROOT/$PDK/libs.tech/xschem/xschemrc") ;;
            esac
            # -x / --no_x（画面なしで netlist だけ作る）ときは XQuartz を起動しない
            for a in "$@"; do
              case "$a" in -x|--no_x) exec ${pkgs.xschem}/bin/xschem "''${args[@]}" "$@" ;; esac
            done
          '';

          magic = withX "magic" "${pkgs.magic}/bin/magic" ''
            # 作業フォルダに .magicrc があればそれを、なければ PDK 付属のものを使う
            args=()
            rc="$PDK_ROOT/$PDK/libs.tech/magic/$PDK.magicrc"
            case " $* " in
              *" -rcfile "*) ;;
              *) if [ ! -f ./.magicrc ] && [ -f "$rc" ]; then args=(-rcfile "$rc"); fi ;;
            esac
            # -dnull（バッチ実行）のときは XQuartz を起動しない
            case " $* " in *" -dnull "*) exec ${pkgs.magic}/bin/magic "''${args[@]}" "$@" ;; esac
          '';

          xterm = withX "xterm" "${pkgs.xterm}/bin/xterm" "args=()";

          # gdsfactory 入りの KLayout（sky130・gf180 の PCell が gdsfactory を使う）。
          # KLayout に組み込まれた Python は KLayout 自身を「Python 本体」だと思っている。
          # gdsfactory が multiprocessing の後始末用プロセスを起動すると KLayout がもう 1 つ起動して待ち続け、
          # KLayout が終われなくなる（Linux ではウィンドウが無限に増える。efabless/sky130_klayout_pdk#45）。
          # 同じ版の本物の Python を教える（macOS の Python が読む環境変数）。
          klayout = pkgs.writeShellScriptBin "klayout" ''
            export PYTHONEXECUTABLE=${pkgs.python3}/bin/python3
            exec ${pkgs.klayout-gdsfactory}/bin/klayout "$@"
          '';

          # ---- PDK の KLayout 部分（PCell を直したもの）-------------------------------

          # sky130・gf180 の PCell は古い gdsfactory 向けで、そのままだと置くと空のセルになる。
          # IIC-OSIC-TOOLS（JKU）が当てている修正を、PDK の KLayout 部分のコピーに当てる。
          # PDK 本体（ciel で取ってハッシュで検証したもの）には手を入れない。patches/iic-osic-tools を参照。
          klayoutTech = {
            sky130 = pkgs.runCommand "klayout-sky130A" { nativeBuildInputs = [ pkgs.python3 ]; } ''
              cp -r ${pdks.sky130}/sky130A/libs.tech/klayout $out
              chmod -R u+w $out
              python3 ${./patches/iic-osic-tools/sky130-pcells.py} $out/python/cells
            '';
            # gf180 は 171 MB のほとんどが LVS のテスト用データなので、PCell（tech/pymacros）だけをコピーし、
            # 残りは PDK 本体へのリンクにする。
            gf180mcu = pkgs.runCommand "klayout-gf180mcuD" { nativeBuildInputs = [ pkgs.patch ]; } ''
              src=${pdks.gf180mcu}/gf180mcuD/libs.tech/klayout
              mkdir -p $out/tech
              for e in "$src"/*; do
                [ "$(basename "$e")" = tech ] || ln -s "$e" $out/
              done
              for e in "$src"/tech/*; do
                case "$(basename "$e")" in
                  pymacros) ;;
                  *.lyt) cp "$e" $out/tech/ ;;
                  *) ln -s "$e" $out/tech/ ;;
                esac
              done
              cp -r "$src"/tech/pymacros $out/tech/pymacros
              chmod -R u+w $out/tech/pymacros
              patch -p1 -d $out/tech/pymacros < ${./patches/iic-osic-tools/gf180mcu-pcells-gdsfactory9.patch}
              patch -p1 -d $out/tech/pymacros < ${./patches/iic-osic-tools/gf180mcu-efuse.patch}
            '';
          };

          # ishi-kai のマクロが結果の表示に使う gnome-terminal の代わり
          gnome-terminal = pkgs.writeShellApplication {
            name = "gnome-terminal";
            runtimeInputs = [
              eda-xserver
              pkgs.xterm
            ];
            text = builtins.readFile ./gnome-terminal.sh;
          };

          # ---- ishi-kai の KLayout マクロ ------------------------------------------

          # macros/ をそのまま並べる。sky130 の LVS マクロは ../lvs/sky130.lvs を読むので、
          # ishi-kai のセットアップと同じく W・L を比べるようにした LVS ルールを lvs/ に置く。
          ishikaiKlayout = {
            sky130 = pkgs.runCommand "ishikai-klayout-sky130" { } ''
              mkdir -p $out/macros $out/lvs
              cp ${ishikai}/sky130/macros/* $out/macros/
              # PEX の設定を、マクロのファイル自体を書き換えて保存する。/nix/store は書き換えられないので外す。
              rm $out/macros/sky130_options.lym
              # xschem は sky130 のトランジスタ等を XM1・XR1 のようなサブサーキット呼び出しで書き出す。
              # ishi-kai の lvs_make は XM を M に直さない（2026-07 にコメントアウトされた）ため、このままだと
              # LVS が回路図を読めず必ず不一致になる（ishi-kai の samples/inverter/SKY130 でも再現）。
              # 公式の LVS ルールに用意されている、X 形式の素子をそのまま読むスイッチを有効にする。
              sed -i 's/^\$schematic = "lvs_temp.cdl"$/&\n$convert_subckts = "true"/' $out/macros/sky130_lvs.lylvs
              grep -q '^\$convert_subckts = "true"$' $out/macros/sky130_lvs.lylvs
              sed -e 's/enable_parameter("A", true)/enable_parameter("W", true)/g' \
                  -e 's/enable_parameter("P", true)/enable_parameter("L", true)/g' \
                  ${pdks.sky130}/sky130A/libs.tech/klayout/lvs/sky130.lvs > $out/lvs/sky130.lvs
            '';
            gf180mcu = pkgs.runCommand "ishikai-klayout-gf180mcu" { } ''
              mkdir -p $out/macros
              cp ${ishikai}/gf180/tech/macros/* $out/macros/
            '';
          };

          # KLAYOUT_HOME の中に、/nix/store のファイルへのリンクを張り直す。
          # マクロは自分と同じフォルダに一時ファイルを書くので、フォルダ自体は書き込めるようにしておく。
          linkIntoKlayoutHome = dir: ''
            for sub in $(cd ${dir} && ls); do
              mkdir -p "$KLAYOUT_HOME/$sub"
              for l in "$KLAYOUT_HOME/$sub"/*; do
                if [ -L "$l" ]; then
                  case "$(readlink "$l")" in /nix/store/*) rm -f "$l" ;; esac
                fi
              done
              ln -sf ${dir}/"$sub"/* "$KLAYOUT_HOME/$sub/"
            done
          '';

          # ---- 環境 -------------------------------------------------------------

          mkPdkShell =
            {
              pdkName,
              pdkRoot,
              label,
              klayoutPath ? "${pdkRoot}/${pdkName}/libs.tech/klayout",
              klayoutrc ? null,
              initialTechnology ? null,
              spiceinit ? null,
              klayoutExtra ? null,
              extraEnv ? { },
            }:
            pkgs.mkShell {
              name = "eda-${pdkName}";
              packages = [
                xschem
                magic
                xterm
                eda-xserver
                gnome-terminal
                klayout
                pkgs.netgen
                ngspice
                # GNU sed（ishi-kai のマクロが GNU の書き方で sed -i を使う）
                pkgs.gnused
                pkgs.xschem
                pkgs.magic
                pkgs.xterm
              ];
              shellHook = ''
                export PDK_ROOT="${pdkRoot}"
                export PDK="${pdkName}"
                export KLAYOUT_PATH="${klayoutPath}"
                export KLAYOUT_HOME="$HOME/.klayout-${pdkName}"
                mkdir -p "$KLAYOUT_HOME"
              ''
              + lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}\n") extraEnv)
              + lib.optionalString (klayoutrc != null) ''
                if [ ! -f "$KLAYOUT_HOME/klayoutrc" ]; then
                  install -m 644 "${klayoutrc}" "$KLAYOUT_HOME/klayoutrc"
                fi
              ''
              # 初回だけ、レイアウトを開いたときの技術を PDK のものにする設定を作る。
              # 技術フォルダにある PDK のマクロ（gf180 の DRC・LVS など）は、技術が合っていないとメニューに出ない。
              + lib.optionalString (initialTechnology != null) ''
                if [ ! -f "$KLAYOUT_HOME/klayoutrc" ]; then
                  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<config>' \
                    ' <initial-technology>${initialTechnology}</initial-technology>' '</config>' \
                    > "$KLAYOUT_HOME/klayoutrc"
                fi
              ''
              + lib.optionalString (spiceinit != null) ''
                export SPICE_USERINIT_DIR="${pkgs.linkFarm "spiceinit-${pdkName}" [ { name = ".spiceinit"; path = spiceinit; } ]}"
              ''
              + lib.optionalString (klayoutExtra != null) (linkIntoKlayoutHome klayoutExtra)
              + ''
                echo "PDK: ${label}  /  xschem, ngspice, klayout, magic, netgen"
              '';
            };

          shortVersion = family: lib.substring 0 7 cielPdks.${family}.version;
        in
        {
          tr1um = mkPdkShell {
            pdkName = "TR-1um";
            pdkRoot = pkgs.linkFarm "pdk-root" [
              {
                name = "TR-1um";
                path = tr1um;
              }
            ];
            label = "TR-1um (${tr1um.shortRev or "local"})";
            klayoutrc = "${tr1um}/libs.tech/klayout/klayoutrc";
          };

          sky130 = mkPdkShell {
            pdkName = "sky130A";
            pdkRoot = pdks.sky130;
            label = "sky130A (open_pdks ${shortVersion "sky130"})";
            # PDK 付属の ngspice 設定（公式の手順ではこれを .spiceinit として使う）
            spiceinit = "${pdks.sky130}/sky130A/libs.tech/ngspice/spinit";
            initialTechnology = "sky130";
            klayoutPath = "${klayoutTech.sky130}";
            klayoutExtra = ishikaiKlayout.sky130;
          };

          gf180 = mkPdkShell {
            pdkName = "gf180mcuD";
            pdkRoot = pdks.gf180mcu;
            label = "gf180mcuD (open_pdks ${shortVersion "gf180mcu"})";
            initialTechnology = "gf180mcu";
            klayoutPath = "${klayoutTech.gf180mcu}";
            klayoutExtra = ishikaiKlayout.gf180mcu;
            # PDK の KLayout マクロが読む（未設定だと D とみなして警告を出す）
            extraEnv.GF_PDK_OPTION = "D";
          };

          # 更新用（scripts/update-pdks.sh が使う）
          inherit pdks;
          ciel = nixpkgs.pdk-ciel;
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          env = mkEnv system;
        in
        {
          inherit (env) tr1um sky130 gf180;
          default = env.tr1um;
        }
      );

      packages = forAllSystems (
        system:
        let
          env = mkEnv system;
        in
        {
          pdk-sky130 = env.pdks.sky130;
          pdk-gf180mcu = env.pdks.gf180mcu;
          inherit (env) ciel;
        }
      );
    };
}
