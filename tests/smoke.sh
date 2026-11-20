#!/usr/bin/env bash
# 環境が一通り動くかを確かめる簡単なテスト（画面は使わない）。
#   nix develop .#tr1um -c ./tests/smoke.sh
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

echo "== PDK: $PDK ($PDK_ROOT)"
test -f "$PDK_ROOT/$PDK/libs.tech/spice/models/ip62_models"

echo "== xschem: PDK の top.sch を netlist に変換"
xschem -x -q -n -s -o "$work" "$PDK_ROOT/$PDK/libs.tech/xschem/top.sch" >/dev/null 2>&1 || true  # 警告があると 0 以外を返すので、出力ファイルで判定する
grep -q "ip62_models" top.spice

echo "== ngspice: PDK のモデルで CMOS インバータの DC 解析"
cat > inv_tb.spice <<EOF
* smoke test inverter
.include $PDK_ROOT/$PDK/libs.tech/spice/models/ip62_models
Vdd vdd 0 5
Vin in 0 0
XMP out in vdd vdd PMOS w=20u l=1u
XMN out in 0 0 NMOS w=10u l=1u
.control
dc Vin 0 5 0.05
meas dc vth when v(out)=2.5
print v(out)[0] v(out)[100]
.endc
.end
EOF
ngspice -b inv_tb.spice > ngspice.log 2>&1 || { cat ngspice.log; exit 1; }
grep -E "^vth|v\(out\)\[" ngspice.log
grep -qE "^vth +=" ngspice.log

echo "== ngspice: 電圧依存容量モデル（F_CSIO）を読めるか"
cat > csio_tb.spice <<EOF
* smoke test F_CSIO
.include $PDK_ROOT/$PDK/libs.tech/spice/models/ip62_models
V1 a 0 1
XC1 a 0 0 F_CSIO c=1p x=10u y=10u m=1
.control
op
print v(a)
.endc
.end
EOF
ngspice -b csio_tb.spice > csio.log 2>&1 || { cat csio.log; exit 1; }
if grep -qiE "unknown parameter|error" csio.log; then cat csio.log; exit 1; fi

echo "== KLayout: TR-1um の技術ファイルとライブラリ"
cat > kl.py <<'EOF'
import pya
techs = pya.Technology.technology_names()
libs = pya.Library.library_names()
print("tech:", techs)
print("libs:", libs)
assert "TR-1um" in techs
assert "TR-1um_stdcell" in libs
EOF
klayout -zz -r kl.py

echo "OK"
