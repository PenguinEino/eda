# ishi-kai の KLayout マクロは、結果を Linux の gnome-terminal で表示する。
#   gnome-terminal --title=T --working-directory=D -- sh -c '...'
# Mac にはないので、同じ引数を受け取って xterm（XQuartz）で開く。

title="EDA"
dir="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --title=*) title="${1#--title=}" ;;
    --working-directory=*) dir="${1#--working-directory=}" ;;
    --) shift; break ;;
  esac
  shift
done

DISPLAY="$(eda-xserver)"
export DISPLAY
cd "$dir"
nohup xterm -T "$title" -e "$@" >/dev/null 2>&1 &

# gnome-terminal と同じく、開いたらすぐ戻る。
# マクロは戻ってから約 1 秒後に一時ファイル（magic に渡す .tcl）を消すので、
# 中のコマンドがそれを読み始められるよう、少しだけ待ってから戻る。
sleep 2
