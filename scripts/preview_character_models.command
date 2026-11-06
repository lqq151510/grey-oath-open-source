#!/bin/zsh
set -eu
project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$project_dir/.tools/Godot.app/Contents/MacOS/Godot" --path "$project_dir" res://scenes/model_gallery.tscn
