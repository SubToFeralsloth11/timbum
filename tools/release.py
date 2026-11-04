#!/usr/bin/env python3
"""Publish a Timbum release that installed games pick up by themselves (scripts/autoload/updater.gd).

    tools/release.py 2.0.2 [--notes FILE] [--dry-run]

1. Sets the version (project.godot and the export presets) and keeps Updater.RUNTIME (engine +
   native plugins) current.
2. Exports the full apps (macOS zip, Windows zip) and one game-data .pck per platform.
3. Writes update.json (version, runtime, pck URL, SHA-256, size per platform) and signs it with the
   owner key (~/.timbum-dev/dev_tag_key.pem) as update.json.sig.
4. Commits the version bump, tags vVERSION, pushes and creates the GitHub release with every file.

Installed games download the matching .pck and swap it in when they close. When RUNTIME changed
(new Godot version or plugin binaries) a .pck can't run on old installs: they are pointed at the
release page for the full app instead, and the script says so.

--dry-run builds and signs everything into build/release/vVERSION/ but doesn't commit, tag, push or
publish (and puts the edited files back afterwards).
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "SubToFeralsloth11/timbum"
KEY = Path.home() / ".timbum-dev" / "dev_tag_key.pem"
UPDATER = ROOT / "scripts" / "autoload" / "updater.gd"
PROJECT = ROOT / "project.godot"
PRESETS = ROOT / "export_presets.cfg"
MANIFEST_PREFIX = b"timbum-update\n"
HEAVY = Path.home() / ".agents" / "bin" / "heavy"
# Native files that must match between an installed app and a .pck.
NATIVE_SUFFIXES = {".dll", ".dylib", ".so", ".gdextension"}
PLATFORMS = {"macos": "macOS", "windows": "Windows"}


def run(*cmd, **kw):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.run([str(c) for c in cmd], check=True, cwd=ROOT, **kw)


def godot(*args):
    cmd = ["godot", "--headless", "--path", ".", *args]
    if HEAVY.exists():
        cmd = [HEAVY, "1200", *cmd]
    run(*cmd)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def runtime_id() -> str:
    """Engine version plus every native plugin file, hashed: equal ids can share .pck files."""
    h = hashlib.sha256(subprocess.run(["godot", "--version"], capture_output=True, text=True, check=True).stdout.strip().encode())
    for p in sorted((ROOT / "addons").rglob("*")):
        inside_framework = any(part.endswith(".framework") for part in p.parts)
        if p.is_file() and (p.suffix in NATIVE_SUFFIXES or inside_framework):
            h.update(str(p.relative_to(ROOT)).encode())
            h.update(sha256(p).encode())
    return h.hexdigest()[:16]


def sub_once(path: Path, pattern: str, repl: str) -> str:
    text = path.read_text()
    new, n = re.subn(pattern, repl, text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"{path.name}: pattern {pattern!r} not found")
    path.write_text(new)
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--notes", type=Path, help="release notes file (Markdown)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    version = a.version
    if not re.fullmatch(r"\d+(\.\d+){1,3}", version):
        sys.exit("version must look like 2.0.2")
    if not KEY.exists():
        sys.exit(f"missing the owner key {KEY}")
    tag = f"v{version}"
    if not a.dry_run:
        if subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip():
            sys.exit("commit or stash your changes first")
        if subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}"], cwd=ROOT,
                          capture_output=True).returncode == 0:
            sys.exit(f"tag {tag} already exists")

    old_runtime = re.search(r'^const RUNTIME := "([0-9a-f]+)"', UPDATER.read_text(), re.M).group(1)
    runtime = runtime_id()
    win_version = ".".join((version.split(".") + ["0"] * 4)[:4])
    originals = {UPDATER: UPDATER.read_text(), PROJECT: PROJECT.read_text(), PRESETS: PRESETS.read_text()}

    def restore():
        for path, text in originals.items():
            path.write_text(text)

    out = ROOT / "build" / "release" / tag
    try:
        sub_once(UPDATER, r'^const RUNTIME := "[0-9a-f]+"', f'const RUNTIME := "{runtime}"')
        sub_once(PROJECT, r'^config/version=".*"$', f'config/version="{version}"')
        sub_once(PRESETS, r'^application/short_version=".*"$', f'application/short_version="{version}"')
        sub_once(PRESETS, r'^application/version=".*"$', f'application/version="{version}"')
        sub_once(PRESETS, r'^application/file_version=".*"$', f'application/file_version="{win_version}"')
        sub_once(PRESETS, r'^application/product_version=".*"$', f'application/product_version="{win_version}"')
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        godot("--export-release", "macOS", out / "Timbum-macOS.zip")
        win = out / "windows"
        win.mkdir()
        godot("--export-release", "Windows", win / "Timbum.exe")
        with zipfile.ZipFile(out / "Timbum-Windows.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in sorted(win.iterdir()):
                z.write(f, f.name)
        shutil.rmtree(win)
        files = {}
        for plat, preset in PLATFORMS.items():
            pck = out / f"timbum-{version}-{plat}.pck"
            godot("--export-pack", preset, pck)
            files[plat] = {
                "url": f"https://github.com/{REPO}/releases/download/{tag}/{pck.name}",
                "sha256": sha256(pck),
                "size": pck.stat().st_size,
            }
        manifest = json.dumps({
            "version": version,
            "runtime": runtime,
            "page": f"https://github.com/{REPO}/releases/tag/{tag}",
            "files": files,
        }, indent=1).encode()
        (out / "update.json").write_bytes(manifest)
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY], input=MANIFEST_PREFIX + manifest,
                             capture_output=True, check=True).stdout
        (out / "update.json.sig").write_text(base64.b64encode(sig).decode())
    except BaseException:
        restore()
        raise

    if runtime != old_runtime:
        print(f"\nRUNTIME changed ({old_runtime} -> {runtime}): installs from before this release can't "
              "take its .pck and will be sent to the release page for the full app.")
    if a.dry_run:
        restore()
        print(f"\nDry run: everything is in {out}; nothing committed or published.")
        return

    run("git", "add", UPDATER, PROJECT, PRESETS)
    if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=ROOT).returncode != 0:
        run("git", "commit", "-m", f"Release {version}")
    run("git", "tag", "-a", tag, "-m", f"Timbum {version}")
    run("git", "push", "origin", "main", tag)
    notes = ["--notes-file", a.notes] if a.notes else ["--notes", f"Timbum {version}. Installed games update themselves."]
    assets = sorted(p for p in out.iterdir() if p.is_file())
    run("gh", "release", "create", tag, "-R", REPO, "--title", f"Timbum {version}", *notes, *assets)
    print(f"\nPublished {tag}: installed games will download it on their next start.")


if __name__ == "__main__":
    main()
