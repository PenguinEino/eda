# opensusi-eda-nix

アナログ回路を設計するための環境を、Mac にネイティブで用意します。VM は使いません。
次の 3 つの PDK に対応しています。

| 環境 | PDK | 取得元 |
|---|---|---|
| `tr1um`（既定） | OpenSUSI TR-1um（OpenSUSI-TR10） | [OpenSUSI/TR-1um](https://github.com/OpenSUSI/TR-1um) の `dev` ブランチ |
| `sky130` | SkyWater sky130A | [ciel-releases](https://github.com/fossi-foundation/ciel-releases) の公式ビルド |
| `gf180` | GlobalFoundries gf180mcuD | 同上 |

- ツールは [nix-eda](https://github.com/fossi-foundation/nix-eda) のビルド済みバイナリを使います。xschem・ngspice・KLayout・magic・netgen が入ります。
- PDK もツールも、版はすべて固定されます（`flake.lock` と `pdks.json`）。誰が入れても同じ中身になります。
- X11 の表示に使う XQuartz も Nix から取ってきて、必要なときに自動で起動します。
- KLayout には [ishi-kai](https://github.com/ishi-kai/OpenEDA-PDK_SetupScript) のメニュー（magic での DRC・PEX、LVS）を追加しています。

## 対応環境

- macOS 14（Sonoma）以降
- Apple Silicon で動作を確認しています。Intel Mac も対象には入れていますが、試していません。

## インストール（最初の 1 回だけ）

Nix（NixOS 公式のインストーラー）を入れます。nix-eda のビルド済みバイナリを使う設定と、ディスクの空きが減ったら古いものを自動で消す設定も一緒に入ります。

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://artifacts.nixos.org/nix-installer | sh -s -- install --extra-conf "
extra-substituters = https://nix-cache.fossi-foundation.org
extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
extra-experimental-features = nix-command flakes
min-free = 10737418240
max-free = 32212254720
"
```

インストールが終わったら、ターミナルを開き直してください。

- `min-free`・`max-free` は「Nix が何かを取ってくるときに空きが 10 GB を切っていたら、30 GB 空くまで、使われていない古いものを消す」という設定です。PDK の古い版はこれで消えます。

## 使い方

```sh
nix develop github:PenguinEino/opensusi-eda-nix          # TR-1um
nix develop github:PenguinEino/opensusi-eda-nix#sky130   # sky130A
nix develop github:PenguinEino/opensusi-eda-nix#gf180    # gf180mcuD
```

これでその PDK 用の環境に入ります。あとはいつもどおりコマンドを打つだけです。

```sh
xschem          # 回路図（XQuartz が自動で起動します）
klayout -e      # レイアウト（PDK の技術ファイル・PCell・DRC/LVS が読み込まれた状態）
ngspice         # シミュレータ
magic           # レイアウト（sky130・gf180 は PDK の設定で起動します）
```

`exit` で環境から抜けます。別の PDK に切り替えるときは、抜けてから入り直します。ターミナルごとに別の PDK を使うこともできます。

- 初回はダウンロードに数分かかります。PDK は sky130 が約 0.3 GB（展開後 2.2 GB）、gf180 が約 0.55 GB（展開後 3.5 GB）です。どちらも ciel が標準で入れるライブラリをそのまま入れています。
- 2 回目からはすぐに入れます。
- GitHub の main が更新されると、次に入ったときに新しい版になります（最大 1 時間遅れます。すぐに取りたいときは `nix develop --refresh …`）。
- 版を固定したいとき（ワークショップなど）は、タグやコミットを付けて入ります。例: `nix develop github:PenguinEino/opensusi-eda-nix/<タグ>#gf180`

### 環境に入ると何が変わるか

そのターミナルの環境変数だけが変わります。Mac の設定や、ホームフォルダの既存のファイルは変わりません。

| 変数 | 中身 |
|---|---|
| `PATH` | xschem・ngspice・klayout・magic・netgen・xterm など |
| `PDK_ROOT`, `PDK` | PDK の場所と名前（`TR-1um`・`sky130A`・`gf180mcuD`） |
| `KLAYOUT_PATH` | PDK の `libs.tech/klayout`。KLayout がここから技術ファイル・PCell・マクロを読みます |
| `KLAYOUT_HOME` | `~/.klayout-<PDK>`。KLayout の設定を PDK ごとに分けます |
| `SPICE_USERINIT_DIR` | sky130 のみ。PDK 付属の ngspice の設定（`spinit`）を `.spiceinit` として読ませます |
| `GF_PDK_OPTION` | gf180 のみ。`D`（PDK の KLayout マクロが読みます） |

ホームフォルダに作るのは `~/.klayout-<PDK>`（KLayout の設定と、下記のマクロへのリンク）と `~/.cache/opensusi-eda`（XQuartz の番号）だけです。

### 設定ファイル

xschem・magic・ngspice の設定は、PDK に入っている公式のものを毎回そのまま読みます（コピーや書き換えはしません）。

| ツール | 読むもの | 作業フォルダにこれがあればそちらを優先 |
|---|---|---|
| xschem | `$PDK_ROOT/$PDK/libs.tech/xschem/xschemrc` | `xschemrc` |
| magic | `$PDK_ROOT/$PDK/libs.tech/magic/$PDK.magicrc` | `.magicrc` |
| ngspice（sky130） | `$PDK_ROOT/$PDK/libs.tech/ngspice/spinit` | `.spiceinit` |

`~/.xschem/xschemrc` や `~/.magicrc` は読みません。

### KLayout

- PDK の技術ファイル・PCell・DRC/LVS のメニューが使えます。
- 最初に入ったときに `~/.klayout-<PDK>/klayoutrc` を作り、開いたレイアウトの技術を PDK のものにします（gf180 の DRC/LVS のメニューは、技術が `gf180mcu` のときだけ出るため）。
- ishi-kai のマクロがメニューの「sky130 PDK」「gf180mcu PDK」に入ります。

| メニュー | sky130 | gf180 |
|---|---|---|
| Run Magic DRC | ○ | ○ |
| Run Magic PEX（RC / C） | ○ | ○ |
| Make netlist for Klayout LVS | ○ | ○ |
| Run Klayout LVS | ○（ishi-kai 版） | ○（PDK 公式） |

ishi-kai のマクロは Linux 向けに書かれているので、Mac で動くように次のようにしています。マクロ本体は書き換えていません（下の 2 か所を除く）。

- 結果の表示に使う `gnome-terminal` の代わりに、同じ引数で xterm（XQuartz）を開くコマンドを入れています。
- `sed` は GNU 版を入れています（マクロが GNU の書き方を使うため）。
- sky130 の LVS は、ishi-kai のセットアップと同じく、W・L で比べるように書き換えた LVS ルールを使います。
- sky130 の LVS マクロに `$convert_subckts = "true"` を足しています。xschem は sky130 のトランジスタを `XM1` のように書き出しますが、ishi-kai の `lvs_make` はこれを変換しないため、そのままでは回路図が読み込めず必ず不一致になります（ishi-kai の `samples/inverter/SKY130` で再現。公式の LVS ルールにある、この形式を読むためのスイッチを有効にしています）。
- sky130 の「Set Options」マクロは入れていません（設定を、マクロのファイル自体を書き換えて保存する作りで、Nix の読み取り専用のファイルとは合わないため）。

### XQuartz

`xschem` などの X11 アプリを起動すると、Nix に入っている XQuartz が自動で立ち上がります。

- すでに公式の XQuartz を使っている場合は、そちらを使います。
- XQuartz を終わらせたいときは、Dock の XQuartz を終了してください。
- 端末から ngspice の `plot` を使うときは、先に `export DISPLAY=$(eda-xserver)` を実行してください。xschem から起動した場合は不要です。

## 動作確認

```sh
nix develop github:PenguinEino/opensusi-eda-nix#sky130 -c bash -c "$(curl -fsSL https://raw.githubusercontent.com/PenguinEino/opensusi-eda-nix/main/tests/smoke.sh)"
```

リポジトリを clone してあるなら、`nix develop .#sky130 -c ./tests/smoke.sh` でも実行できます（`tr1um`・`gf180` も同じ）。次のことを確かめます。

- xschem で PDK の回路図を netlist にできる
- ngspice で PDK のモデルを使ってインバータの DC 解析ができる
- magic が PDK の設定を読める
- KLayout が技術ファイルを読み、PCell でトランジスタを置ける

## バージョン

| | バージョン | 固定している場所 |
|---|---|---|
| nix-eda | 7.20.0 | `flake.nix` |
| xschem | 3.4.7 | nix-eda |
| ngspice | 45（nixpkgs 版。理由は「既知の問題」） | nix-eda が使う nixpkgs |
| KLayout | 0.30.13 | nix-eda |
| magic / netgen | 8.3.693 / 1.5.329 | nix-eda |
| TR-1um | `dev` ブランチ | `flake.lock` |
| sky130 / gf180mcu | open_pdks のコミット | `pdks.json` |
| ishi-kai のマクロ | `main` ブランチ | `flake.lock` |

GitHub Actions が毎週、TR-1um・ishi-kai・sky130・gf180 を最新にして、テストが通れば PR を作ります。
手で更新するときは次を実行してから commit します。

```sh
nix flake update tr1um ishikai   # TR-1um と ishi-kai
./scripts/update-pdks.sh         # sky130・gf180（ciel-releases の最新版と、その中身のハッシュ）
```

## 既知の問題

- **ngspice 47 は TR-1um の容量モデルを読めません。** `F_CSIO`（`models_IP62_cap_v5p1.lib`）の式で `unknown parameter (e9)` というエラーになります。そのため nix-eda の 47 ではなく、nixpkgs の 45 を使っています（45 はビルド済みが cache.nixos.org にあります。TR-1um の結果は VM の 46 と一致することを確かめています）。
- **sky130 の KLayout の PCell は使えません。** 公式（と ishi-kai 版）の PCell は古い gdsfactory（8.x）向けで、nix-eda の gdsfactory 9.x では置くと空のセルになるため、gdsfactory 自体を入れていません。トランジスタなどの生成は magic でできます。
- **gf180 は、KLayout API 版の PCell（`gf180mcu_klayoutapi` ライブラリ）を使ってください。** gdsfactory 版（`gf180mcu` ライブラリ）は同じ理由で入っていません。
- **2025 年のワークショップの例題の多くは、モデルを `.include $::LIB/../ip62_models` で読み込んでいます。** 今の TR-1um ではモデルが `libs.tech/spice/models/ip62_models` にあるため、このパスでは見つかりません。`$::LIB/ip62_models` に直すと動きます。

## アンインストール

```sh
/nix/nix-installer uninstall
rm -rf ~/.klayout-TR-1um ~/.klayout-sky130A ~/.klayout-gf180mcuD ~/.cache/opensusi-eda
```

Nix ごと、すべて消えます。
