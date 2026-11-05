#!/bin/zsh
set -e
project_dir="${0:A:h}"
godot_bin="$project_dir/.tools/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$godot_bin" ]]; then
  print "缺少本地 Godot，请先运行 scripts/setup_engine.py --editor-only。"
  read -r "?按回车关闭。"
  exit 1
fi
exec "$godot_bin" --path "$project_dir"
