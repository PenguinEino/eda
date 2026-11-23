# opensusi-eda-nix

アナログ回路設計の環境（xschem・ngspice・KLayout・magic・netgen）を、VM なしで Mac にネイティブで用意します。
ツールと PDK の版は固定されるので、誰が入れても同じ環境になります。

| 環境 | PDK |
|---|---|
| `tr1um`（既定） | OpenSUSI TR-1um（`dev` ブランチ） |
| `sky130` | sky130A（ciel の公式ビルド） |
| `gf180` | gf180mcuD（ciel の公式ビルド） |

macOS 14 以降。Apple Silicon で確認しています。

## インストール（最初の 1 回だけ）

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://artifacts.nixos.org/nix-installer | sh -s -- install --extra-conf "
extra-substituters = https://nix-cache.fossi-foundation.org
extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
extra-experimental-features = nix-command flakes
min-free = 10737418240
max-free = 32212254720
"
```

終わったらターミナルを開き直します。

## 使い方

```sh
nix develop github:PenguinEino/opensusi-eda-nix          # TR-1um
nix develop github:PenguinEino/opensusi-eda-nix#sky130   # sky130A
nix develop github:PenguinEino/opensusi-eda-nix#gf180    # gf180mcuD
```

入ったら `xschem`、`klayout -e`、`ngspice`、`magic` をいつもどおり使えます。`exit` で抜けます。

- 初回は数分かかります（PDK は sky130 が約 0.3 GB、gf180 が約 0.55 GB）。
- XQuartz は自動で起動します。別に入れる必要はありません。
- 変わるのはそのターミナルの環境変数だけです。設定ファイルは PDK 付属のものをそのまま読みます。作業フォルダに `xschemrc`・`.magicrc`・`.spiceinit` があればそちらが優先されます。
- KLayout の設定は PDK ごとに `~/.klayout-<PDK>` に分かれます。
- 版を固定したいとき（ワークショップなど）は `nix develop github:PenguinEino/opensusi-eda-nix/<タグ>#gf180` のようにします。

### KLayout のメニュー（sky130・gf180）

[ishi-kai](https://github.com/ishi-kai/OpenEDA-PDK_SetupScript) のマクロを入れています。メニューの「sky130 PDK」「gf180mcu PDK」から、magic の DRC・PEX と LVS を実行できます。

Mac で動かすため、結果は xterm で表示します。また、sky130 の LVS が xschem の netlist（`XM1` 形式）を読めるように設定を 1 行足しています。

## 既知の問題

- **ngspice は 45 を使っています。** 47 は TR-1um の容量モデル（`F_CSIO`）を読めません。
- **sky130・gf180 の KLayout の PCell は、上流のままだと今の gdsfactory で動きません。** [IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS) と同じ修正を当てて使えるようにしています（[patches/iic-osic-tools](patches/iic-osic-tools)）。
- **gf180 の `gf180mcu_klayoutapi` ライブラリの `diode_dw2ps`・`diode_pw2dw` は、置くと KLayout が止まります**（PDK 側の不具合）。`gf180mcu` ライブラリの同じ名前の PCell を使ってください。
- **2025 年のワークショップの例題では、モデルのパスの直しが要ることがあります。** `.include $::LIB/../ip62_models` を `$::LIB/ip62_models` に直してください。

## 動作確認・更新

```sh
nix develop .#sky130 -c ./tests/smoke.sh    # テスト（tr1um・gf180 も同様）
nix flake update tr1um ishikai              # TR-1um と ishi-kai のマクロを更新
./scripts/update-pdks.sh                    # sky130・gf180 を ciel の最新版に更新
```

GitHub Actions が毎週これらを更新し、テストが通れば PR を作ります。

## アンインストール

```sh
/nix/nix-installer uninstall
rm -rf ~/.klayout-TR-1um ~/.klayout-sky130A ~/.klayout-gf180mcuD ~/.cache/opensusi-eda
```
