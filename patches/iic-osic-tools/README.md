# IIC-OSIC-TOOLS の PCell 修正

sky130A と gf180mcuD の KLayout PCell は古い gdsfactory 向けに書かれていて、今の gdsfactory 9 では
置くと空のセルになる。[IIC-OSIC-TOOLS](https://github.com/iic-jku/IIC-OSIC-TOOLS)（JKU）が PDK を入れるときに
当てている修正を、そのまま使っている。

| ファイル | 元 |
|---|---|
| `sky130-pcells.py` | `_build/images/open_pdks/scripts/install_ciel.sh` の sky130A の PCell 修正を Python にしたもの |
| `gf180mcu-pcells-gdsfactory9.patch` | `_build/images/open_pdks/patches/` から無変更 |
| `gf180mcu-efuse.patch` | 同上 |

- 取得元: commit `f15ef6a303ef3aa814c54e7006e82c965c6eba59`（2026-11-23）
- ライセンス: Apache-2.0（`LICENSE`）。Copyright 2022-2026 Harald Pretl and Georg Zachl, Johannes Kepler University
- 上流の PDK 側で直ったら（例: gf180 は fossi-foundation/globalfoundries-pdk-libs-gf180mcu_fd_pr#3）、ここは消してよい。
