#!/usr/bin/env python3
"""Install the pinned, checksum-verified Godot toolchain inside this project."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request
import zipfile

VERSION = "4.7.2"
TAG = f"{VERSION}-stable"
ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tools"
DOWNLOADS = TOOLS / "downloads"
BASE_URL = f"https://github.com/godotengine/godot-builds/releases/download/{TAG}"
EDITOR = f"Godot_v{TAG}_macos.universal.zip"
TEMPLATES = f"Godot_v{TAG}_export_templates.tpz"


def read_url(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "GreyOath-Toolchain/0.1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def sha512(path: Path) -> str:
    digest = hashlib.sha512()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_verified(filename: str, expected: str) -> Path:
    target = DOWNLOADS / filename
    if target.exists() and sha512(target) == expected:
        print(f"verified cached {filename}", flush=True)
        return target
    partial = target.with_suffix(target.suffix + ".part")
    for attempt in range(3):
        try:
            request = urllib.request.Request(
                f"{BASE_URL}/{filename}", headers={"User-Agent": "GreyOath-Toolchain/0.1"}
            )
            with urllib.request.urlopen(request, timeout=60) as response, partial.open("wb") as stream:
                total = int(response.headers.get("Content-Length", 0))
                received = 0
                last_report = time.monotonic()
                while chunk := response.read(2 * 1024 * 1024):
                    stream.write(chunk)
                    received += len(chunk)
                    if time.monotonic() - last_report >= 10:
                        print(f"download {filename}: {received // 1048576}/{total // 1048576} MiB", flush=True)
                        last_report = time.monotonic()
            actual = sha512(partial)
            if actual != expected:
                raise RuntimeError(f"SHA-512 mismatch for {filename}")
            os.replace(partial, target)
            print(f"SHA-512 verified {filename}", flush=True)
            return target
        except Exception as error:
            if attempt == 2:
                raise
            print(f"download retry {attempt + 1}/2: {type(error).__name__}", flush=True)
            time.sleep(2 ** attempt)
    raise RuntimeError("unreachable")


def install_editor(checksums: dict[str, str]) -> dict:
    archive = download_verified(EDITOR, checksums[EDITOR])
    executable = TOOLS / "Godot.app/Contents/MacOS/Godot"
    if not executable.exists():
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), str(TOOLS)], check=True)
    executable.chmod(executable.stat().st_mode | 0o111)
    version = subprocess.check_output([str(executable), "--version"], text=True).strip()
    if not version.startswith(VERSION + ".stable"):
        raise RuntimeError(f"Unexpected editor version: {version}")
    print(f"EDITOR_READY {executable}\nEDITOR_VERSION {version}", flush=True)
    return {"file": EDITOR, "sha512": checksums[EDITOR], "version": version, "path": str(executable)}


def install_templates(checksums: dict[str, str]) -> dict:
    archive = download_verified(TEMPLATES, checksums[TEMPLATES])
    destination = TOOLS / "export_templates" / f"{VERSION}.stable"
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        candidates = [name for name in bundle.namelist() if name.endswith("/macos.zip")]
        if len(candidates) != 1:
            raise RuntimeError(f"Expected exactly one macos.zip, found {len(candidates)}")
        with bundle.open(candidates[0]) as source, (destination / "macos.zip.tmp").open("wb") as output:
            shutil.copyfileobj(source, output)
        os.replace(destination / "macos.zip.tmp", destination / "macos.zip")
    with zipfile.ZipFile(destination / "macos.zip") as macos:
        corrupt = macos.testzip()
        if corrupt:
            raise RuntimeError(f"Corrupt macOS template member: {corrupt}")
        names = macos.namelist()
        if not any("Contents/MacOS/" in name for name in names):
            raise RuntimeError("macOS export template has no executable")
    print(f"TEMPLATES_READY {destination / 'macos.zip'}", flush=True)
    return {"file": TEMPLATES, "sha512": checksums[TEMPLATES], "path": str(destination / "macos.zip")}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--editor-only", action="store_true")
    group.add_argument("--templates-only", action="store_true")
    args = parser.parse_args()
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    checksum_data = read_url(f"{BASE_URL}/SHA512-SUMS.txt")
    (DOWNLOADS / "SHA512-SUMS.txt").write_bytes(checksum_data)
    checksums = {}
    for line in checksum_data.decode().splitlines():
        parts = line.split()
        if len(parts) == 2:
            checksums[parts[1].lstrip("*")] = parts[0]
    required = [EDITOR] if args.editor_only else [TEMPLATES] if args.templates_only else [EDITOR, TEMPLATES]
    for filename in required:
        if len(checksums.get(filename, "")) != 128:
            raise RuntimeError(f"Missing official SHA-512 checksum: {filename}")
    jobs = ([install_editor] if args.editor_only else [install_templates] if args.templates_only
            else [install_editor, install_templates])
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for future in concurrent.futures.as_completed([pool.submit(job, checksums) for job in jobs]):
            results.append(future.result())
    report = {"release": TAG, "source": BASE_URL, "checksums_source": f"{BASE_URL}/SHA512-SUMS.txt", "verified": results}
    (TOOLS / "toolchain-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print("Toolchain installation and verification complete.", flush=True)


if __name__ == "__main__":
    main()
