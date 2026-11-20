# X11 アプリ（xschem など）を起動する前に呼ばれ、使える DISPLAY を標準出力に返す。
#
# 1. すでに使える DISPLAY があればそれを使う（公式 XQuartz を入れている人など）
# 2. 前回このスクリプトが起動した XQuartz が生きていればそれを使う
# 3. どちらもなければ /nix/store の XQuartz を空いている番号で起動する
#
# launchd への登録や sudo は不要。XQuartz は終了するまで動き続ける。

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/opensusi-eda"
state_file="$state_dir/display"

alive() { DISPLAY="$1" xset q >/dev/null 2>&1; }

if [ -n "${DISPLAY:-}" ] && alive "$DISPLAY"; then
  echo "$DISPLAY"; exit 0
fi

if [ -f "$state_file" ]; then
  d=$(cat "$state_file")
  if alive "$d"; then echo "$d"; exit 0; fi
fi

mkdir -p "$state_dir"
n=1
while [ -e "/tmp/.X11-unix/X$n" ] || [ -e "/tmp/.X$n-lock" ]; do
  if alive ":$n"; then echo ":$n" > "$state_file"; echo ":$n"; exit 0; fi
  n=$((n + 1))
done

nohup Xquartz ":$n" -nolisten tcp >"$state_dir/xquartz.log" 2>&1 &
i=0
until alive ":$n"; do
  i=$((i + 1))
  if [ "$i" -gt 100 ]; then
    echo "XQuartz を起動できませんでした。ログ: $state_dir/xquartz.log" >&2
    exit 1
  fi
  sleep 0.1
done
DISPLAY=":$n" nohup quartz-wm >"$state_dir/quartz-wm.log" 2>&1 &
echo ":$n" > "$state_file"
echo ":$n"
