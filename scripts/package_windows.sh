#!/usr/bin/env bash
# 灰誓 · Windows x86_64 release packaging.
# Exports the "Windows" preset, verifies the artifact statically and produces a ZIP.
# The Windows binary cannot be executed on a macOS build host; see the report.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
godot_bin="$project_root/.tools/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$godot_bin" ]]; then
  godot_bin="$(command -v godot || true)"
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
  printf '%s\n' 'Missing Godot 4.7.2 stable. Run: python3 scripts/setup_engine.py --editor-only' >&2
  exit 1
fi
if [[ "$("$godot_bin" --version)" != 4.7.2.stable* ]]; then
  printf '%s\n' 'The pinned Godot 4.7.2 stable engine is required.' >&2
  exit 1
fi

build_dir="$(python3 - "${GREY_OATH_BUILD_DIR:-$project_root/build/windows-release}" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"
case "$project_root/" in
  "$build_dir/"*)
    printf '%s\n' 'Build output must not be the project directory or one of its parents.' >&2
    exit 1
    ;;
esac
for artifact in "$build_dir/灰誓.exe" "$build_dir/灰誓.pck" "$build_dir/灰誓-Windows-x86_64.zip"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    printf 'Output already exists: %s\nChoose a fresh GREY_OATH_BUILD_DIR.\n' "$artifact" >&2
    exit 1
  fi
done
mkdir -p "$build_dir"

"$godot_bin" --headless --path "$project_root" --editor --import > "$build_dir/import.log" 2>&1
if /usr/bin/grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$build_dir/import.log"; then
  cat "$build_dir/import.log" >&2
  exit 1
fi
"$godot_bin" --headless --path "$project_root" --export-release "Windows" "$build_dir/灰誓.exe" > "$build_dir/export.log" 2>&1
if /usr/bin/grep -Eq '^(WARNING|ERROR)|SCRIPT ERROR|Parse Error|Export failed|Failed to load script' "$build_dir/export.log"; then
  cat "$build_dir/export.log" >&2
  exit 1
fi

python3 - "$build_dir" "$project_root" <<'PY'
from pathlib import Path
import hashlib, json, re, sys, zipfile

root, project = Path(sys.argv[1]), Path(sys.argv[2])
exe_path, pck_path = root / '灰誓.exe', root / '灰誓.pck'
zip_path = root / '灰誓-Windows-x86_64.zip'

config = (project / 'project.godot').read_text(encoding='utf-8')
match = re.search(r'^config/version="([^"]+)"', config, re.M)
if not match:
    raise SystemExit('Cannot read config/version from project.godot')
version = match.group(1)

exe = exe_path.read_bytes()
pck = pck_path.read_bytes()
export_log = (root / 'export.log').read_text(encoding='utf-8', errors='replace')
log_clean = not any(
    line.startswith(('WARNING', 'ERROR'))
    or 'SCRIPT ERROR' in line or 'Parse Error' in line or 'Export failed' in line
    for line in export_log.splitlines()
)
checks = {
    'exe_mz_header': exe[:2] == b'MZ',
    'pck_gdpc_header': pck[:4] == b'GDPC',
    'pe_version_resource': version.encode('utf-16le') in exe,
    'pe_product_name': '灰誓'.encode('utf-16le') in exe,
    'pck_has_catalog': b'data/catalog.json' in pck,
    'pck_has_update_public_key': b'update_public.pem' in pck,
    # Script export mode 2 stores scenes as .scn plus a .remap entry.
    'pck_has_main_scene_remap': b'main.tscn.remap' in pck,
    'pck_has_binary_main_scene': b'main.scn' in pck,
    'export_log_clean': log_clean,
}
if not all(checks.values()):
    print(json.dumps(checks, ensure_ascii=False, indent=2))
    raise SystemExit('Windows artifact verification failed')

with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in (exe_path, pck_path):
        archive.write(path, path.name)

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

artifacts = [
    {'file': path.name, 'bytes': path.stat().st_size, 'sha256': sha256(path)}
    for path in (exe_path, pck_path, zip_path)
]
report = {
    'platform': 'Windows',
    'architecture': 'x86_64',
    'version': version,
    'engine': '4.7.2.stable',
    'bundle': ['灰誓.exe', '灰誓.pck'],
    'signed': False,
    'code_signing': 'Not signed: no Windows code-signing certificate available on the build host.',
    'runtime_validation': 'Static verification only. The Windows binary was not executed; the build host is macOS.',
    'published': False,
    'checks': checks,
    'artifacts': artifacts,
}
(root / 'package-verification-windows.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
