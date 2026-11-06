#!/usr/bin/env bash
# 灰誓 · UI 截图捕获（原生渲染）
#
# 用法：
#   bash scripts/capture_ui.sh             # 跑 tests/capture_ui.gd 并校验 14 张截图
#   bash scripts/capture_ui.sh --keep      # 校验时允许沿用上次生成的文件（不检查本次是否重写）
#   bash scripts/capture_ui.sh --check-only  # 只校验现有截图，不启动 Godot（离线/CI）
#   bash scripts/capture_ui.sh --timeout 300
#
# 校验口径：
#   * 14 个预期文件名全部存在（名单与 tests/capture_ui.gd 的 _shot 调用一致）；
#   * 每个文件字节数 > 0，PNG 像素宽高 > 0；
#   * 默认还要求文件在本次运行期间被重写（防止上半场成功、下半场失败却看着像通过）。
#
# 截图由 tests/capture_ui.gd 写入 docs/evidence/ui-rebuild-20261104/，属于生成物，不要提交。

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

GODOT="${GODOT:-.tools/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="$(command -v godot)"
	elif command -v godot4 >/dev/null 2>&1; then
		GODOT="$(command -v godot4)"
	else
		echo "错误：找不到 Godot 可执行文件。设置 GODOT=/path/to/Godot 后重试。" >&2
		exit 2
	fi
fi

OUT_DIR="docs/evidence/ui-rebuild-20261104"
EXPECTED_COUNT=14
TIMEOUT_SEC="${GODOT_CAPTURE_TIMEOUT:-300}"
REQUIRE_FRESH=1
CHECK_ONLY=0

while [ $# -gt 0 ]; do
	case "$1" in
		--keep) REQUIRE_FRESH=0 ;;
		--check-only) CHECK_ONLY=1; REQUIRE_FRESH=0 ;;
		--timeout) shift; TIMEOUT_SEC="${1:-300}" ;;
		--timeout=*) TIMEOUT_SEC="${1#--timeout=}" ;;
		-h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "未知参数：$1（见 --help）" >&2; exit 2 ;;
	esac
	shift
done

EXPECTED_NAMES="screen-01-menu
screen-02-roles
screen-03-map
screen-04-battle
screen-05-reward
screen-05-shop
screen-05-rest
screen-05-event
screen-05-treasure
screen-05-victory
screen-05-defeat
screen-06-deck
screen-07-relics
screen-08-battle-1280"

mkdir -p "$OUT_DIR"

echo "== 捕获 UI 截图 =="
echo "Godot: $("$GODOT" --version 2>/dev/null | head -n 1)"
echo "脚本:  tests/capture_ui.gd（原生，无 --headless）"
echo "输出:  $OUT_DIR"
echo "-------------------------------------------------------------------------------"

START_EPOCH=$(date +%s)
LOG="${TMPDIR:-/tmp}/greyoath-capture-ui.$$.log"

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "（--check-only：跳过渲染，只校验已有文件）"
	RC=0
elif command -v timeout >/dev/null 2>&1; then
	timeout "$TIMEOUT_SEC" "$GODOT" --path "$ROOT" --script tests/capture_ui.gd 2>&1 | tee "$LOG"
	RC="${PIPESTATUS[0]:-1}"
elif command -v gtimeout >/dev/null 2>&1; then
	gtimeout "$TIMEOUT_SEC" "$GODOT" --path "$ROOT" --script tests/capture_ui.gd 2>&1 | tee "$LOG"
	RC="${PIPESTATUS[0]:-1}"
else
	"$GODOT" --path "$ROOT" --script tests/capture_ui.gd 2>&1 | tee "$LOG"
	RC="${PIPESTATUS[0]:-1}"
fi

echo "-------------------------------------------------------------------------------"
echo "capture_ui.gd rc=$RC"

PROBLEMS=""
if [ "$RC" -ne 0 ]; then
	PROBLEMS="$PROBLEMS capture_ui.gd 退出码 $RC"
	if [ "$RC" -eq 124 ]; then
		PROBLEMS="$PROBLEMS（超时 ${TIMEOUT_SEC}s）"
	fi
fi

# 逐张检查：存在、字节数、PNG 像素尺寸、（可选）本次重写。
FOUND=0
for name in $EXPECTED_NAMES; do
	path="$OUT_DIR/$name.png"
	if [ ! -f "$path" ]; then
		printf '  %-26s MISSING\n' "$name.png"
		PROBLEMS="$PROBLEMS 缺 $name.png"
		continue
	fi

	bytes=$(wc -c <"$path" | tr -d ' ')
	dims=""
	if command -v python3 >/dev/null 2>&1; then
		dims=$(python3 - "$path" <<'PY'
import struct, sys
path = sys.argv[1]
try:
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        print("not-png")
    else:
        w, h = struct.unpack(">II", head[16:24])
        print(f"{w}x{h}")
except Exception as exc:  # noqa: BLE001
    print(f"error:{exc}")
PY
)
	fi

	mtime=$(date -r "$path" +%s 2>/dev/null || echo 0)
	fresh=1
	if [ "$REQUIRE_FRESH" -eq 1 ] && [ "$mtime" -lt "$(( START_EPOCH - 1 ))" ]; then
		fresh=0
	fi

	status="OK"
	case "$dims" in
		"") ;; # 没有 python3，退化为只看字节数
		not-png) status="NOT-PNG"; PROBLEMS="$PROBLEMS $name.png 不是 PNG" ;;
		error:*) status="DIM-ERR"; PROBLEMS="$PROBLEMS $name.png 尺寸读取失败(${dims#error:})" ;;
		*x0|0x*) status="ZERO-DIM"; PROBLEMS="$PROBLEMS $name.png 像素尺寸为 ${dims}" ;;
	esac
	if [ "$bytes" -le 0 ]; then
		status="EMPTY"
		PROBLEMS="$PROBLEMS $name.png 为空文件"
	fi
	if [ "$fresh" -eq 0 ]; then
		status="$status/STALE"
		PROBLEMS="$PROBLEMS $name.png 本次未重新生成（--keep 可放宽）"
	fi

	printf '  %-26s %-10s %8s bytes  %s\n' "$name.png" "$status" "$bytes" "${dims:-(dims unknown)}"
	[ "$status" = "OK" ] || [ "$status" = "OK/STALE" ] && FOUND=$(( FOUND + 1 ))
done

COUNT=$(ls -1 "$OUT_DIR"/screen-*.png 2>/dev/null | wc -l | tr -d ' ')
echo "-------------------------------------------------------------------------------"
echo "预期 ${EXPECTED_COUNT} 张，目录内共 ${COUNT} 张 screen-*.png，本次校验通过 ${FOUND} 张。"
if [ "$COUNT" -lt "$EXPECTED_COUNT" ]; then
	PROBLEMS="$PROBLEMS 目录内只有 ${COUNT} 张（要求 >= ${EXPECTED_COUNT}）"
fi

if [ -n "$PROBLEMS" ]; then
	echo "失败：${PROBLEMS# }"
	echo "日志：$LOG" 
	exit 1
fi

echo "结果：14 张截图齐全且尺寸有效。"
exit 0