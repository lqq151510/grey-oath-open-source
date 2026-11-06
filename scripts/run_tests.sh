#!/usr/bin/env bash
# 灰誓 · headless 测试入口
#
# 用法：
#   bash scripts/run_tests.sh                  # 默认整套 headless（跳过需原生渲染的用例）
#   bash scripts/run_tests.sh --native         # headless + 原生渲染用例 + capture_ui 截图校验
#   bash scripts/run_tests.sh --headless-only  # 只跑 headless 组（即使同时给了 --native）
#   bash scripts/run_tests.sh --only test_x    # 只跑一个用例（名字可带 tests/ 前缀与 .gd 后缀）
#   bash scripts/run_tests.sh --list           # 只列出当前会跑哪些用例
#
# 分组：
#   headless 组（默认执行）：tests/test_*.gd 去掉 DENYLIST / HELPERS，当前 27 个。
#   原生组（默认不执行，需 --native）：test_character_art_insertion、test_combat_presentation，
#     以及 tests/capture_ui.gd（校验 14 张截图）。原生组会开窗口、抢焦点，和别人在改 ui/ 时
#     不要并行跑。
#
# 约定：
#   * 正式 headless 测试 = tests/test_*.gd 里去掉 DENYLIST（原生渲染 / 辅助脚本）。
#     新增 tests/test_foo.gd 会被自动纳入，不需要改这个脚本；要排除就加进 DENYLIST。
#   * 判定：rc != 0 或输出里出现 "FAIL:" 都算失败。
#   * 单个用例默认 240s 超时（GODOT_TEST_TIMEOUT 可覆盖），超时记为失败（rc=124）。
#   * 日志写到临时目录，默认不往仓库里落生成物。

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

GODOT_TEST_TIMEOUT="${GODOT_TEST_TIMEOUT:-240}"
NATIVE=0
HEADLESS_ONLY=0
ONLY=""
LIST_ONLY=0
LOG_DIR="${GODOT_TEST_LOG_DIR:-}"

# 需要原生渲染（窗口/真实 GPU 帧）的用例：headless 下会阻塞或拿不到画面。
DENYLIST="test_character_art_insertion test_combat_presentation"
NATIVE_TESTS="test_character_art_insertion test_combat_presentation"

# 不是正式用例、只是调试/截图辅助脚本的：不参与测试矩阵。
HELPERS="test_ui_headless ui_shell ui_manual ui_smoke capture_ui"

CAPTURE_DIR="docs/evidence/ui-rebuild-20261104"
CAPTURE_MIN=14

usage() {
	sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
		--native) NATIVE=1 ;;
		--headless-only) HEADLESS_ONLY=1 ;;
		--only) shift; ONLY="${1:-}" ;;
		--only=*) ONLY="${1#--only=}" ;;
		--list) LIST_ONLY=1 ;;
		--logdir) shift; LOG_DIR="${1:-}" ;;
		--logdir=*) LOG_DIR="${1#--logdir=}" ;;
		-h|--help) usage; exit 0 ;;
		*) echo "未知参数：$1（见 --help）" >&2; exit 2 ;;
	esac
	shift
done

if [ -z "$LOG_DIR" ]; then
	LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/greyoath-tests.XXXXXX")"
fi
mkdir -p "$LOG_DIR"

now_ms() {
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import time; print(int(time.time()*1000))'
	elif command -v perl >/dev/null 2>&1; then
		perl -MTime::HiRes=time -e 'printf("%d\n", time()*1000)'
	else
		echo $(( $(date +%s) * 1000 ))
	fi
}

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_BIN="gtimeout"
fi

is_in() {
	# $1 = 待查名字，其余 = 名单
	local needle="$1" item
	shift
	for item in "$@"; do
		[ "$item" = "$needle" ] && return 0
	done
	return 1
}

# 收集 headless 用例（按文件名排序，顺序稳定）。
collect_tests() {
	local path name
	for path in tests/test_*.gd; do
		[ -f "$path" ] || continue
		name="$(basename "$path" .gd)"
		is_in "$name" $DENYLIST && continue
		is_in "$name" $HELPERS && continue
		echo "$name"
	done
}

normalize_name() {
	local raw="$1"
	raw="${raw##*/}"
	raw="${raw%.gd}"
	printf '%s' "$raw"
}

PASS=0
FAIL=0
FAILED_NAMES=""
TOTAL_MS=0
INDEX=0
TOTAL=0
RC=0
LAST=""
DUR_MS=0

print_row() {
	# $1 序号 $2 总数 $3 名字 $4 rc $5 毫秒 $6 最后一行
	local line="$6"
	if [ "${#line}" -gt 200 ]; then
		line="${line:0:200}…"
	fi
	printf '[%2d/%2d] %-28s rc=%-3s %8.2fs  %s\n' \
		"$1" "$2" "$3" "$4" "$(awk -v ms="$5" 'BEGIN{printf "%.2f", ms/1000}')" "$line"
}

run_case() {
	# $1 = 测试名；$2 = headless|native。结果写入全局 RC / LAST / DUR_MS。
	local name="$1" mode="$2"
	local script="tests/$name.gd"
	local log="$LOG_DIR/$name.log"
	local args=()
	local start end
	[ "$mode" = "headless" ] && args+=(--headless)

	start=$(now_ms)
	if [ -n "$TIMEOUT_BIN" ] && [ "$mode" = "headless" ]; then
		"$TIMEOUT_BIN" "$GODOT_TEST_TIMEOUT" "$GODOT" "${args[@]}" --path "$ROOT" --script "$script" >"$log" 2>&1
		RC=$?
	else
		"$GODOT" "${args[@]}" --path "$ROOT" --script "$script" >"$log" 2>&1
		RC=$?
	fi
	end=$(now_ms)

	LAST="$(grep -iE 'RESULT|checks|PASSED|FAIL' "$log" | tail -n 1)"
	if [ -z "$LAST" ] && [ "$RC" -ne 0 ]; then
		LAST="$(tail -n 2 "$log" | tr '\n' ' ')"
	fi
	DUR_MS=$(( end - start ))
}

record() {
	# $1 名字 $2 rc $3 毫秒 $4 最后一行
	local name="$1" rc="$2" dur="$3" last="$4"
	local failed=0
	TOTAL_MS=$(( TOTAL_MS + dur ))
	[ "$rc" -ne 0 ] && failed=1
	printf '%s' "$last" | grep -q 'FAIL:' && failed=1
	# Godot 在 --script 模式下遇到解析/加载错误仍可能返回 0，必须自己识别。
	if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$LOG_DIR/$name.log" 2>/dev/null; then
		failed=1
	fi
	if [ "$failed" -eq 1 ]; then
		FAIL=$(( FAIL + 1 ))
		FAILED_NAMES="$FAILED_NAMES $name"
		print_row "$INDEX" "$TOTAL" "$name" "$rc" "$dur" "$last"
		echo "        ↳ 失败，日志：$LOG_DIR/$name.log"
	else
		PASS=$(( PASS + 1 ))
		print_row "$INDEX" "$TOTAL" "$name" "$rc" "$dur" "$last"
	fi
}

print_header() {
	echo "灰誓 · 测试矩阵"
	echo "Godot: $("$GODOT" --version 2>/dev/null | head -n 1)"
	echo "项目:  $ROOT"
	echo "日志:  $LOG_DIR"
	echo "-------------------------------------------------------------------------------"
}

# ---------------- 单用例模式 ----------------
if [ -n "$ONLY" ]; then
	ONLY="$(normalize_name "$ONLY")"
	if [ ! -f "tests/$ONLY.gd" ]; then
		echo "错误：找不到 tests/$ONLY.gd" >&2
		exit 2
	fi
	print_header
	INDEX=1
	TOTAL=1
	if is_in "$ONLY" $NATIVE_TESTS; then
		echo "（该用例需要原生渲染，已自动去掉 --headless）"
		run_case "$ONLY" native
	else
		run_case "$ONLY" headless
	fi
	record "$ONLY" "$RC" "$DUR_MS" "$LAST"
	echo "-------------------------------------------------------------------------------"
	if [ "$FAIL" -eq 0 ]; then
		echo "结果：PASS（1 个用例，总耗时 $(awk -v ms="$TOTAL_MS" 'BEGIN{printf "%.2f", ms/1000}')s）"
		exit 0
	fi
	echo "结果：FAIL（$ONLY）"
	exit 1
fi

# ---------------- 总览模式 ----------------
TESTS="$(collect_tests)"
for ignored in $TESTS; do TOTAL=$(( TOTAL + 1 )); done

if [ "$LIST_ONLY" -eq 1 ]; then
	echo "$TESTS"
	exit 0
fi

if [ "$TOTAL" -eq 0 ]; then
	echo "错误：tests/ 下没有找到任何正式用例。" >&2
	exit 2
fi

print_header
echo "headless 用例：$TOTAL 个"
echo "  排除原生渲染：$DENYLIST"
echo "  排除辅助脚本：$HELPERS"
echo "-------------------------------------------------------------------------------"

for name in $TESTS; do
	INDEX=$(( INDEX + 1 ))
	run_case "$name" headless
	record "$name" "$RC" "$DUR_MS" "$LAST"
done

if [ "$NATIVE" -eq 0 ] || [ "$HEADLESS_ONLY" -eq 1 ]; then
	echo "-------------------------------------------------------------------------------"
	if [ "$NATIVE" -eq 1 ] && [ "$HEADLESS_ONLY" -eq 1 ]; then
		echo "原生渲染组：已按 --headless-only 跳过（$NATIVE_TESTS）+ capture_ui"
	else
		echo "原生渲染组未执行：$NATIVE_TESTS + capture_ui（需要时加 --native）"
	fi
fi

if [ "$NATIVE" -eq 1 ] && [ "$HEADLESS_ONLY" -eq 0 ]; then
	echo "-------------------------------------------------------------------------------"
	echo "原生渲染用例（不带 --headless）："
	for name in $NATIVE_TESTS; do
		INDEX=$(( INDEX + 1 ))
		TOTAL=$(( TOTAL + 1 ))
		run_case "$name" native
		record "$name" "$RC" "$DUR_MS" "$LAST"
	done

	echo "-------------------------------------------------------------------------------"
	echo "UI 截图捕获：tests/capture_ui.gd"
	INDEX=$(( INDEX + 1 ))
	TOTAL=$(( TOTAL + 1 ))
	run_case "capture_ui" native
	record "capture_ui" "$RC" "$DUR_MS" "$LAST"

	SHOT_COUNT=0
	BAD_SHOT=""
	if [ -d "$CAPTURE_DIR" ]; then
		for shot in "$CAPTURE_DIR"/screen-*.png; do
			[ -f "$shot" ] || continue
			size=$(wc -c <"$shot" | tr -d ' ')
			if [ "$size" -gt 0 ]; then
				SHOT_COUNT=$(( SHOT_COUNT + 1 ))
			else
				BAD_SHOT="$BAD_SHOT $(basename "$shot")"
			fi
		done
	fi
	printf '%-34s 截图 %d 张（要求 >= %d）%s\n' "capture_ui screenshots" "$SHOT_COUNT" "$CAPTURE_MIN" "${BAD_SHOT:+  空文件:$BAD_SHOT}"
	if [ "$SHOT_COUNT" -lt "$CAPTURE_MIN" ] || [ -n "$BAD_SHOT" ]; then
		FAIL=$(( FAIL + 1 ))
		FAILED_NAMES="$FAILED_NAMES capture_ui:screenshots"
		echo "        ↳ 失败：$CAPTURE_DIR/screen-*.png 数量或尺寸不达标。"
	fi
fi

echo "-------------------------------------------------------------------------------"
echo "汇总：PASS=$PASS  FAIL=$FAIL  用例数=$TOTAL  总耗时 $(awk -v ms="$TOTAL_MS" 'BEGIN{printf "%.1f", ms/1000}')s"
if [ "$FAIL" -ne 0 ]; then
	echo "失败用例：$FAILED_NAMES"
	echo "日志目录：$LOG_DIR"
	exit 1
fi
echo "结果：全部通过。"
exit 0