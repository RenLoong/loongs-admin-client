#!/usr/bin/env python3
"""Rename shadcn_ui Geist variable-font files to ASCII-safe names and patch manifests.

What they are:
  Geist[wght].ttf / GeistMono[wght].ttf — variable fonts from the shadcn_ui package
  ([wght] = weight axis). Defaults for shadcn UI text / monospace. Our app already
  sets ShadTextTheme(family: PingFangSC); these still ship because the package
  registers them. Flutter web encodes brackets as %%5Bwght%%5D in the built path.

Rename (same string length so AssetManifest.bin length prefixes stay valid):
  Geist%%5Bwght%%5D.ttf     -> Geist-wght-font.ttf
  GeistMono%%5Bwght%%5D.ttf -> GeistMono-wght-font.ttf
"""
from __future__ import annotations

import sys
from pathlib import Path

# Keep UTF-8 byte length identical for AssetManifest.bin safety.
RENAMES = {
    "Geist%5Bwght%5D.ttf": "Geist-wght-font.ttf",
    "GeistMono%5Bwght%5D.ttf": "GeistMono-wght-font.ttf",
    "Geist[wght].ttf": "Geist-wght-font.ttf",
    "GeistMono[wght].ttf": "GeistMono-wght-font.ttf",
}


def patch_text(text: str) -> str:
    for old, new in RENAMES.items():
        text = text.replace(old, new)
    return text


def patch_bytes(data: bytes) -> bytes:
    out = data
    for old, new in RENAMES.items():
        ob, nb = old.encode("utf-8"), new.encode("utf-8")
        if len(ob) != len(nb) and ob in out:
            # Only allow unequal replace for the bracket form (not in .bin usually)
            if old.startswith("Geist%") or old.startswith("GeistMono%"):
                raise SystemExit(f"length mismatch for {old!r} -> {new!r}: {len(ob)} vs {len(nb)}")
        out = out.replace(ob, nb)
    return out


def fix_assets_dir(assets: Path) -> list[str]:
    logs: list[str] = []
    fonts_dir = assets / "packages" / "shadcn_ui" / "fonts"
    if not fonts_dir.is_dir():
        return [f"skip (no fonts dir): {fonts_dir}"]

    for old, new in RENAMES.items():
        src = fonts_dir / old
        dst = fonts_dir / new
        if not src.is_file():
            continue
        if dst.exists() and dst.resolve() != src.resolve():
            dst.unlink()
        src.rename(dst)
        logs.append(f"rename {old} -> {new}")

    for name in ("FontManifest.json", "AssetManifest.bin.json"):
        path = assets / name
        if path.is_file():
            path.write_text(patch_text(path.read_text(encoding="utf-8")), encoding="utf-8")
            logs.append(f"patched {name}")

    amb = assets / "AssetManifest.bin"
    if amb.is_file():
        amb.write_bytes(patch_bytes(amb.read_bytes()))
        logs.append("patched AssetManifest.bin")

    return logs or [f"nothing to rename under {fonts_dir}"]


def main() -> int:
    roots = [Path(a) for a in sys.argv[1:]] or [
        Path("/www/wwwroot/loong-swoole/admin/client/build/web/assets"),
        Path("/www/wwwroot/loong-swoole/admin/server/apps/Admin/public/web/assets"),
    ]
    for root in roots:
        print(f"== {root}")
        if not root.is_dir():
            print("  missing")
            continue
        for line in fix_assets_dir(root):
            print(" ", line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
