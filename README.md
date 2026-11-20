# opensusi-eda-nix

OpenSUSI TR-1um（OpenSUSI-TR10）でアナログ回路を設計するための環境を、Mac にネイティブで用意します。
VM は使いません。

- ツールは [nix-eda](https://github.com/fossi-foundation/nix-eda) のビルド済みバイナリを使います。xschem・ngspice・KLayout・magic・netgen が入ります。
- PDK は [OpenSUSI/TR-1um](https://github.com/OpenSUSI/TR-1um) の `dev` ブランチを使います。
- バージョンはすべて `flake.lock` で固定されるので、誰が入れても同じ中身になります。
- X11 の表示に使う XQuartz も Nix から取ってきて、必要なときに自動で起動します。別途インストールする必要はありません。

## 対応環境

- macOS 14（Sonoma）以降
- Apple Silicon で動作を確認しています。Intel Mac も対象には入れていますが、試していません。

## インストール（最初の 1 回だけ）

Nix をインストールします。nix-eda のビルド済みバイナリを使う設定も一緒に入ります。

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --extra-conf "
extra-substituters = https://nix-cache.fossi-foundation.org
extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
"
```

インストールが終わったら、ターミナルを開き直してください。

## 使い方

```sh
nix develop github:PenguinEino/opensusi-eda-nix
```

これで TR-1um 用の環境に入ります。あとはいつもどおりコマンドを打つだけです。

```sh
xschem          # 回路図（XQuartz が自動で起動します）
klayout -e      # レイアウト（TR-1um の技術ファイル、PCell、ライブラリが読み込まれた状態）
ngspice         # シミュレータ
```

`exit` で環境から抜けます。

- 初回はダウンロードに数分かかります。ngspice だけは手元でビルドされるので、さらに 2 分ほどかかります。
- 2 回目からは一瞬で入れます。

### 環境に入ると何が変わるか

そのターミナルの環境変数だけが変わります。ホームフォルダや Mac の設定は変わりません。

| 変数 | 中身 |
|---|---|
| `PATH` | xschem・ngspice・klayout・magic・netgen・xterm |
| `PDK_ROOT`, `PDK` | TR-1um の場所。xschem の `xschemrc` がこれを読みます |
| `KLAYOUT_PATH` | TR-1um の `libs.tech/klayout`。KLayout がここから技術ファイルを読みます |
| `KLAYOUT_HOME` | `~/.klayout-TR-1um`。KLayout の設定を PDK ごとに分けます |

### xschem の設定

- 作業フォルダに `xschemrc` があれば、それを使います。
- なければ TR-1um 付属の `xschemrc` を使います。`~/.xschem/xschemrc` は読みません。

### XQuartz について

`xschem` などの X11 アプリを起動すると、Nix に入っている XQuartz が自動で立ち上がります。

- すでに公式の XQuartz を使っている場合は、そちらを使います。
- XQuartz を終わらせたいときは、Dock の XQuartz を終了してください。
- 端末から ngspice の `plot` を使うときは、先に `export DISPLAY=$(eda-xserver)` を実行してください。xschem から起動した場合は不要です。

## 動作確認

```sh
nix develop github:PenguinEino/opensusi-eda-nix -c bash -c "$(curl -fsSL https://raw.githubusercontent.com/PenguinEino/opensusi-eda-nix/main/tests/smoke.sh)"
```

リポジトリを clone してあるなら、`nix develop -c ./tests/smoke.sh` でも実行できます。xschem の netlist、ngspice の DC 解析、KLayout への TR-1um の読み込みを確かめます。

## バージョン

| | バージョン |
|---|---|
| nix-eda | 7.20.0 |
| xschem | 3.4.7 |
| ngspice | 46（理由は下の「既知の問題」を参照） |
| KLayout | 0.30.13 |
| magic / netgen | 8.3.693 / 1.5.329 |
| TR-1um | `dev` ブランチ。コミットは `flake.lock` を参照 |

TR-1um の `dev` は、GitHub Actions が毎週更新の PR を作ります。
手で更新するときは次のコマンドを実行してから commit します。

```sh
nix flake update tr1um
```

## 既知の問題

- **ngspice 47 は TR-1um の容量モデルを読めません。** `F_CSIO`（`models_IP62_cap_v5p1.lib`）の式で `unknown parameter (e9)` というエラーになります。45 と 46 では読めるので、ngspice は 46 に固定しています。
- **2025 年のワークショップの例題の多くは、モデルを `.include $::LIB/../ip62_models` で読み込んでいます。** 今の TR-1um ではモデルが `libs.tech/spice/models/ip62_models` にあるため、このパスでは見つかりません。`$::LIB/ip62_models` に直すと動きます。

## アンインストール

```sh
/nix/nix-installer uninstall
```

Nix ごと、すべて消えます。
