#!/usr/bin/env python3
"""Export a cumulative macOS PCK patch and sign its local update manifest."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parent.parent
GODOT = PROJECT / ".tools/Godot.app/Contents/MacOS/Godot"
PUBLIC_KEY = PROJECT / "data/update_public.pem"
DEFAULT_KEY = Path.home() / "Library/Application Support/灰誓发行/update-signing-key.pem"
PRODUCT = "com.zebao.greyoath"
MAX_PACK_BYTES = 512 * 1024 * 1024


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run_godot(*args: str) -> None:
    result = subprocess.run(
        [str(GODOT), "--headless", "--path", str(PROJECT), *args],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if result.returncode or re.search(
        r"SCRIPT ERROR:|Parse Error:|Export failed|Failed to load script", result.stdout
    ):
        raise ValueError(result.stdout.strip())


def build_update(base_app: Path, revision: int, output: Path, key: Path) -> None:
    with (base_app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version = re.search(
        r'^config/version="([^"]+)"$', (PROJECT / "project.godot").read_text(), re.MULTILINE
    )
    if (
        version is None
        or info.get("CFBundleIdentifier") != PRODUCT
        or info.get("CFBundleShortVersionString") != version.group(1)
    ):
        raise ValueError("底包必须是与当前项目版本相同的《灰誓》macOS App。")
    if not 1 <= revision <= 2**53 - 1:
        raise ValueError("补丁序号必须是 1 到 9007199254740991 之间的整数。")
    if not stat.S_ISREG(key.stat().st_mode) or key.stat().st_mode & 0o077:
        raise ValueError("签名私钥必须是仅当前用户可读写的普通文件（chmod 600）。")
    public_key = subprocess.check_output(["openssl", "pkey", "-in", str(key), "-pubout"])
    if public_key.strip() != PUBLIC_KEY.read_bytes().strip():
        raise ValueError("私钥与项目内置的更新公钥不匹配。")
    if not subprocess.check_output([str(GODOT), "--version"], text=True).startswith("4.7.2.stable"):
        raise ValueError("补丁必须使用项目固定的 Godot 4.7.2 导出。")

    base_pack = base_app / "Contents/Resources/灰誓.pck"
    if "," in str(base_pack):
        raise ValueError("Godot 将逗号解释为多个底包。请使用不含逗号的底包路径。")
    base_sha256 = file_sha256(base_pack)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".patch-", dir=output) as tmp:
        staging = Path(tmp)
        pack = staging / "content.pck"
        run_godot("--editor", "--import")
        run_godot("--export-patch", "macOS", str(pack), "--patches", str(base_pack))
        size = pack.stat().st_size
        if not 0 < size <= MAX_PACK_BYTES or file_sha256(base_pack) != base_sha256:
            raise ValueError("补丁大小超限，或导出期间底包发生了变化。")
        digest = file_sha256(pack)
        payload = {
            "schema": 1,
            "product": PRODUCT,
            "base_version": version.group(1),
            "base_sha256": base_sha256,
            "revision": revision,
            "pack": f"{digest}.pck",
            "size": size,
            "sha256": digest,
        }
        manifest = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        signature = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", str(key)], input=manifest
        )
        envelope = {
            "payload": base64.b64encode(manifest).decode("ascii"),
            "signature": base64.b64encode(signature).decode("ascii"),
        }
        update = staging / "update.json"
        update.write_text(json.dumps(envelope, indent=2) + "\n", encoding="utf-8")
        # Publish the immutable payload first, then switch the manifest in one rename.
        os.replace(pack, output / payload["pack"])
        os.replace(update, output / update.name)
    print(f"已生成第 {revision} 号补丁，目标底包 {version.group(1)}，大小 {size} 字节。")
    print(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-app", type=Path, required=True, help="交付时保留的原始 .app")
    parser.add_argument("--revision", type=int, required=True, help="正整数补丁序号")
    parser.add_argument("--output-dir", type=Path, required=True, help="本地补丁输出目录")
    parser.add_argument("--private-key", type=Path, default=DEFAULT_KEY, help="仓库外的 RSA 私钥")
    args = parser.parse_args()
    try:
        build_update(
            args.base_app.expanduser().resolve(), args.revision,
            args.output_dir.expanduser().resolve(), args.private_key.expanduser().resolve(),
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"补丁打包失败：{error}\n")


if __name__ == "__main__":
    main()
