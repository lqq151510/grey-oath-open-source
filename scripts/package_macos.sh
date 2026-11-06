#!/bin/bash
# Build locally, verify the ad-hoc signature, then create ZIP and DMG artifacts.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
godot_bin="$project_root/.tools/Godot.app/Contents/MacOS/Godot"
template_zip="$project_root/.tools/export_templates/4.7.2.stable/macos.zip"
build_dir="${GREY_OATH_BUILD_DIR:-$project_root/build}"
build_dir="$(python3 - "$build_dir" <<'PY'
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
app_path="$build_dir/灰誓.app"
zip_path="$build_dir/灰誓-macOS.zip"
dmg_path="$build_dir/灰誓-macOS.dmg"

if [[ ! -x "$godot_bin" || ! -f "$template_zip" ]]; then
  printf '%s\n' 'Missing local toolchain. Run: python3 scripts/setup_engine.py' >&2
  exit 1
fi
if [[ "$("$godot_bin" --version)" != 4.7.2.stable* ]]; then
  printf '%s\n' 'The pinned Godot 4.7.2 stable engine is required.' >&2
  exit 1
fi
for artifact in "$app_path" "$zip_path" "$dmg_path"; do
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    printf 'Output already exists: %s\nChoose a fresh GREY_OATH_BUILD_DIR to preserve previous packages.\n' "$artifact" >&2
    exit 1
  fi
done
mkdir -p "$build_dir"
touch "$build_dir/.gdignore"

"$godot_bin" --headless --path "$project_root" --editor --import > "$build_dir/import.log" 2>&1
if /usr/bin/grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$build_dir/import.log"; then
  cat "$build_dir/import.log" >&2
  exit 1
fi
"$godot_bin" --headless --path "$project_root" --export-release macOS "$app_path" > "$build_dir/export.log" 2>&1
if /usr/bin/grep -Eq 'SCRIPT ERROR:|Parse Error:|Export failed|Failed to load script' "$build_dir/export.log"; then
  cat "$build_dir/export.log" >&2
  exit 1
fi
[[ -d "$app_path/Contents" ]]
bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")"
for architecture in arm64 x86_64; do
  /usr/bin/lipo "$app_path/Contents/MacOS/$bundle_executable" -verify_arch "$architecture"
done
/usr/bin/lipo -archs "$app_path/Contents/MacOS/$bundle_executable" > "$build_dir/architectures.txt"
/usr/bin/codesign --force --deep --sign - "$app_path" > "$build_dir/signing.log" 2>&1
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" >> "$build_dir/signing.log" 2>&1
/usr/bin/codesign -dv --verbose=2 "$app_path" >> "$build_dir/signing.log" 2>&1
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

package_stage="$(mktemp -d "$build_dir/.package.XXXXXX")"
cleanup() { /bin/rm -rf "$package_stage"; }
trap cleanup EXIT
/usr/bin/ditto "$app_path" "$package_stage/灰誓.app"
/bin/ln -s /Applications "$package_stage/Applications"
/usr/bin/hdiutil create -volname 灰誓 -srcfolder "$package_stage" -ov -format UDZO "$dmg_path" > "$build_dir/dmg.log" 2>&1
/usr/bin/hdiutil verify "$dmg_path" >> "$build_dir/dmg.log" 2>&1

python3 - "$build_dir" <<'PY'
from pathlib import Path
import hashlib, json, plistlib, sys
root = Path(sys.argv[1])
artifacts = []
for filename in ['灰誓-macOS.zip', '灰誓-macOS.dmg']:
    path = root / filename
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(block)
    artifacts.append({'file': filename, 'bytes': path.stat().st_size, 'sha256': digest.hexdigest()})
with (root / '灰誓.app/Contents/Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
with (root / '灰誓.app/Contents/Resources/灰誓.pck').open('rb') as stream:
    base_digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        base_digest.update(block)
report = {
    'bundle_identifier': info.get('CFBundleIdentifier'),
    'version': info.get('CFBundleShortVersionString'),
    'engine': '4.7.2.stable',
    'architecture': (root / 'architectures.txt').read_text().strip().split(),
    'signature': 'ad-hoc; codesign --verify --deep --strict passed',
    'notarized': False,
    'published': False,
    'local_update_base_sha256': base_digest.hexdigest(),
    'artifacts': artifacts,
    'runtime_validation': 'Not inferred from export. Record native playtesting separately.'
}
(root / 'package-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
PY
