#!/usr/bin/env bash
# 環境が一通り動くかを確かめる簡単なテスト（画面は使わない）。
#   nix develop .#tr1um  -c ./tests/smoke.sh
#   nix develop .#sky130 -c ./tests/smoke.sh
#   nix develop .#gf180  -c ./tests/smoke.sh
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

pdk="$PDK_ROOT/$PDK"
echo "== PDK: $PDK ($PDK_ROOT)"
test -d "$pdk/libs.tech"

# 時間がかかりすぎたら止める（KLayout が終わらなくなる不具合を見逃さないため）
with_timeout() {
  local t=$1; shift
  set -m
  "$@" & local pid=$!
  set +m
  for ((i = 0; i < t * 4; i++)); do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid"; return $?; fi
    sleep 0.25
  done
  kill -9 -- "-$pid" 2>/dev/null || true
  echo "TIMEOUT: $* が ${t} 秒で終わらなかった" >&2
  return 124
}

# xschem で回路図を netlist にする（警告があると 0 以外を返すので、出力ファイルで判定する）
netlist() {
  xschem -x -q -n -s -o "$work" "$1" >/dev/null 2>&1 || true
  test -s "$work/$(basename "${1%.sch}").spice"
}

# インバータの DC 解析をして、しきい値（出力が VDD/2 になる入力電圧）を表示する
inverter_dc() {
  local header=$1 vdd=$2 pmos=$3 nmos=$4
  cat > inv_tb.spice <<EOF
* smoke test inverter
$header
Vdd vdd 0 $vdd
Vin in 0 0
$pmos
$nmos
.control
dc Vin 0 $vdd 0.01
meas dc vth when v(out)=$(awk "BEGIN{print $vdd/2}")
.endc
.end
EOF
  ngspice -b inv_tb.spice > inv.log 2>&1 || { cat inv.log; return 1; }
  grep -E "^vth +=" inv.log || { cat inv.log; return 1; }
}

case "$PDK" in
  TR-1um)
    echo "== xschem: PDK の top.sch を netlist に変換"
    netlist "$pdk/libs.tech/xschem/top.sch"
    grep -q "ip62_models" top.spice

    echo "== ngspice: PDK のモデルで CMOS インバータの DC 解析"
    inverter_dc ".include $pdk/libs.tech/spice/models/ip62_models" 5 \
      "XMP out in vdd vdd PMOS w=20u l=1u" \
      "XMN out in 0 0 NMOS w=10u l=1u"

    echo "== ngspice: 電圧依存容量モデル（F_CSIO）を読めるか"
    cat > csio_tb.spice <<EOF
* smoke test F_CSIO
.include $pdk/libs.tech/spice/models/ip62_models
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
    tech=TR-1um
    pcell_lib=TR-1um
    pcell=fet_n
    ;;

  sky130A)
    echo "== xschem: PDK のテスト回路図（リングオシレータ）を netlist に変換"
    netlist "$pdk/libs.tech/xschem/sky130_tests/test_inv.sch"
    grep -q "sky130.lib.spice" test_inv.spice

    echo "== ngspice: PDK 付属の spinit を読んでいるか"
    printf '* spinit\n.control\nif $?skywaterpdk\necho SPINIT_LOADED\nend\n.endc\n.end\n' > spinit_tb.spice
    ngspice -b spinit_tb.spice > spinit.log 2>&1 || true
    grep -q SPINIT_LOADED spinit.log

    echo "== ngspice: PDK のモデルで CMOS インバータの DC 解析"
    inverter_dc ".lib $pdk/libs.tech/combined/sky130.lib.spice tt" 1.8 \
      "XMP out in vdd vdd sky130_fd_pr__pfet_01v8 W=2 L=0.15" \
      "XMN out in 0 0 sky130_fd_pr__nfet_01v8 W=1 L=0.15"
    tech=sky130
    pcell_lib=  # sky130 の PCell は古い gdsfactory が要るので入れていない（README の既知の問題）
    pcell=
    ;;

  gf180mcuD)
    echo "== xschem: PDK のテスト回路図（nfet_03v3）を netlist に変換して、そのまま流す"
    netlist "$pdk/libs.tech/xschem/tests/test_nfet_03v3.sch"
    ngspice -b test_nfet_03v3.spice > nfet.log 2>&1 || { cat nfet.log; exit 1; }
    grep -q "No. of Data Rows" nfet.log

    echo "== ngspice: PDK のモデルで CMOS インバータの DC 解析"
    inverter_dc ".include $pdk/libs.tech/ngspice/design.ngspice
.lib $pdk/libs.tech/ngspice/sm141064.ngspice typical" 3.3 \
      "XMP out in vdd vdd pfet_03v3 W=2u L=0.28u" \
      "XMN out in 0 0 nfet_03v3 W=1u L=0.28u"
    tech=gf180mcu
    pcell_lib=gf180mcu_klayoutapi
    pcell=nfet
    ;;

  *)
    echo "知らない PDK: $PDK" >&2
    exit 1
    ;;
esac

if [ -f "$pdk/libs.tech/magic/$PDK.magicrc" ]; then
  echo "== magic: PDK の設定（magicrc）と tech を読めるか"
  printf 'puts "TECH=[tech name]"\nquit -noprompt\n' > tech.tcl
  magic -dnull -noconsole tech.tcl > magic.log 2>&1 || true
  grep -q "TECH=$PDK" magic.log
fi

echo "== KLayout: 技術ファイルを読み、PCell でトランジスタを置けるか"
cat > kl.py <<EOF
import pya
techs = pya.Technology.technology_names()
print("tech:", techs)
assert "$tech" in techs
if "$pcell_lib":
    ly = pya.Layout()
    top = ly.create_cell("top")
    # 技術ごとのライブラリは、技術名も渡さないと見つからないことがある
    lib = pya.Library.library_by_name("$pcell_lib", "$tech") or pya.Library.library_by_name("$pcell_lib")
    assert lib is not None, "PCell ライブラリ $pcell_lib がない"
    pcell_id = lib.layout().pcell_id("$pcell")
    assert pcell_id is not None, "PCell $pcell がない"
    ci = ly.add_pcell_variant(lib, pcell_id, {})
    top.insert(pya.CellInstArray(ci, pya.Trans()))
    print("$pcell_lib/$pcell:", top.bbox())
    assert not top.bbox().empty(), "PCell $pcell の中身が空"
EOF
with_timeout 120 klayout -zz -r kl.py

if [ -d "$KLAYOUT_HOME/macros" ] && ls "$KLAYOUT_HOME/macros" | grep -q '_magic_drc.lym'; then
  echo "== ishi-kai の KLayout マクロ"
  ls "$KLAYOUT_HOME/macros"
  for m in "$KLAYOUT_HOME"/macros/*.lym; do test -r "$m"; done
fi

echo "OK"
