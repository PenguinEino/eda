#!/usr/bin/env bash
# 環境に入るときに「手元でビルドされるもの」が、このリポジトリの小さなラッパーと PDK だけかを確かめる。
# xschem・KLayout・ngspice などがキャッシュから外れて手元でビルドされるようになったら失敗する。
#   ./scripts/check-cache.sh sky130
set -euo pipefail
cd "$(dirname "$0")/.."

shell=$1
system=$(nix eval --raw --impure --expr builtins.currentSystem)
out=$(nix build --dry-run ".#devShells.$system.$shell" 2>&1)

built=$(printf '%s\n' "$out" |
  sed -n '/will be built:/,/will be fetched/p' |
  grep -o '/nix/store/[^ ]*\.drv' |
  sed -E 's|/nix/store/[a-z0-9]{32}-||; s|\.drv$||' || true)

echo "手元でビルドされるもの:"
printf '  %s\n' $built

# このリポジトリが作るもの（中身はスクリプトやリンクだけ）と、ciel で取ってくる PDK
allowed='^(eda-.*|xschem|magic|xterm|gnome-terminal|eda-xserver|pdk-root|pdk-(sky130|gf180mcu)-[0-9a-f]{7}|ishikai-klayout-.*|spiceinit-.*)$'
bad=$(printf '%s\n' $built | grep -vE "$allowed" || true)
if [ -n "$bad" ]; then
  echo "キャッシュにないため手元でビルドされるもの:" >&2
  printf '  %s\n' $bad >&2
  exit 1
fi
echo "OK"
