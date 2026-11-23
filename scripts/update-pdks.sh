#!/usr/bin/env bash
# sky130・gf180mcu を ciel-releases の最新版に上げ、pdks.json の版とハッシュを書き換える。
#   ./scripts/update-pdks.sh
# 変わったものを UPDATE_SUMMARY（指定があれば）に 1 行ずつ書く。
set -euo pipefail
cd "$(dirname "$0")/.."

fake="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
ciel="$(nix build --no-link --print-out-paths .#ciel)/bin/ciel"
summary="${UPDATE_SUMMARY:-/dev/null}"

set_field() { # family field value
  local tmp
  tmp=$(mktemp)
  jq --arg f "$1" --arg k "$2" --arg v "$3" '.[$f][$k] = $v' pdks.json > "$tmp"
  mv "$tmp" pdks.json
}

for family in sky130 gf180mcu; do
  latest=$("$ciel" ls-remote --pdk-family "$family" | head -1)
  current=$(jq -r --arg f "$family" '.[$f].version' pdks.json)
  if [ "$latest" = "$current" ]; then
    echo "$family: 最新のまま（${current:0:7}）"
    continue
  fi
  echo "$family: ${current:0:7} → ${latest:0:7}"

  # 版を書き換え、いったん仮のハッシュでビルドして、本当のハッシュを Nix に教えてもらう
  set_field "$family" version "$latest"
  set_field "$family" hash "$fake"
  hash=$(nix build --no-link ".#pdk-$family" 2>&1 | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | head -1 || true)
  if [ -z "$hash" ]; then
    echo "$family: ハッシュを取得できませんでした" >&2
    exit 1
  fi
  set_field "$family" hash "$hash"
  nix build --no-link ".#pdk-$family" # 正しいハッシュで通ることを確かめる

  echo "$family ${current:0:7} → ${latest:0:7}" >> "$summary"
done
