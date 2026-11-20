{
  description = "OpenSUSI TR-1um (OpenSUSI-TR10) 向けのアナログ設計環境（macOS ネイティブ、nix-eda ベース）";

  inputs = {
    # EDA ツール一式。FOSSi Foundation がビルド済みバイナリを配っている。
    nix-eda.url = "github:fossi-foundation/nix-eda/7.20.0";

    # PDK。dev ブランチを追う（実際のコミットは flake.lock で固定される）。
    tr1um = {
      url = "github:OpenSUSI/TR-1um/dev";
      flake = false;
    };
  };

  outputs =
    { self, nix-eda, tr1um, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nix-eda.inputs.nixpkgs.lib.genAttrs systems (system: f system);

      mkEnv =
        system:
        let
          pkgs = nix-eda.legacyPackages.${system};
          lib = pkgs.lib;

          # ngspice 47 は TR-1um の容量モデル（F_CSIO）の式を読めない
          # （"unknown parameter (e9)"）。45・46 では読めるので 46 に固定する。
          ngspice = pkgs.ngspice.override {
            version = "46";
            sha256 = "sha256-oNFpmvGUCwZkknbc1v9aVmyMDK0Bsve16Z3tu01kwZs=";
          };

          # xschem や magic を起動する前に XQuartz を用意する
          eda-xserver = pkgs.writeShellApplication {
            name = "eda-xserver";
            runtimeInputs = [ pkgs.xquartz pkgs.quartz-wm pkgs.xset ];
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

          # PDK ごとの環境を作る
          mkPdkShell =
            { pdkName, pdkSrc }:
            let
              pdkRoot = pkgs.linkFarm "pdk-root" [ { name = pdkName; path = pdkSrc; } ];
              rcfile = "${pdkSrc}/libs.tech/xschem/xschemrc";
              xschem = withX "xschem" "${pkgs.xschem}/bin/xschem" ''
                # 作業フォルダに xschemrc があればそれを、なければ PDK のものを使う
                args=()
                [ -f ./xschemrc ] || args=(--rcfile "${rcfile}")
                # -x / --no_x（画面なしで netlist だけ作る）ときは XQuartz を起動しない
                for a in "$@"; do
                  case "$a" in -x|--no_x) exec ${pkgs.xschem}/bin/xschem "''${args[@]}" "$@" ;; esac
                done
              '';
            in
            pkgs.mkShell {
              name = "eda-${pdkName}";
              packages = [
                xschem
                (withX "xterm" "${pkgs.xterm}/bin/xterm" "args=()")
                (withX "magic" "${pkgs.magic}/bin/magic" ''
                  args=()
                  # -dnull（バッチ実行）のときは XQuartz を起動しない
                  case " $* " in *" -dnull "*) exec ${pkgs.magic}/bin/magic "$@" ;; esac
                '')
                eda-xserver
                pkgs.klayout
                pkgs.xschem
                pkgs.magic
                pkgs.netgen
                ngspice
                pkgs.xterm
              ];
              shellHook = ''
                export PDK_ROOT="${pdkRoot}"
                export PDK="${pdkName}"
                export KLAYOUT_PATH="${pdkSrc}/libs.tech/klayout"
                export KLAYOUT_HOME="$HOME/.klayout-${pdkName}"
                if [ ! -f "$KLAYOUT_HOME/klayoutrc" ]; then
                  mkdir -p "$KLAYOUT_HOME"
                  install -m 644 "${pdkSrc}/libs.tech/klayout/klayoutrc" "$KLAYOUT_HOME/klayoutrc"
                fi
                echo "PDK: ${pdkName} (${tr1um.shortRev or "local"})  /  xschem, ngspice, klayout, magic, netgen"
              '';
            };
        in
        {
          tr1um = mkPdkShell { pdkName = "TR-1um"; pdkSrc = tr1um; };
        };
    in
    {
      devShells = forAllSystems (
        system:
        let
          envs = mkEnv system;
        in
        envs // { default = envs.tr1um; }
      );
    };
}
