#!/usr/bin/env python3
"""Post-process Flutter web build output.

Moves root-level *.js into js/, writes domain.js beside index.html,
patches index.html and js/flutter_bootstrap.js so the loader finds
entrypoint + service worker under js/.

Usage:
  python3 tools/reorganize_web_js.py <public_web_dir> <api_base_url>
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path


def _js_string_literal(value: str) -> str:
    """Emit a single-quoted JS string literal (escape \\ and ')."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def patch_index(index: Path) -> None:
    html = index.read_text(encoding="utf-8")
    # Drop any existing domain.js tags (idempotent).
    html = re.sub(
        r"[ \t]*<script\s+src=[\"']domain\.js[\"']\s*>\s*</script>\s*\n?",
        "",
        html,
        flags=re.IGNORECASE,
    )
    # Point bootstrap at js/flutter_bootstrap.js
    html = re.sub(
        r"(src=[\"'])(?:\./)?(?:js/)?flutter_bootstrap\.js([\"'])",
        r"\1js/flutter_bootstrap.js\2",
        html,
        flags=re.IGNORECASE,
    )
    # Insert domain.js (sync) immediately before bootstrap.
    if "domain.js" not in html:
        html, n = re.subn(
            r"([ \t]*)(<script\s+[^>]*src=[\"']js/flutter_bootstrap\.js[\"'][^>]*>\s*</script>)",
            r'\1<script src="domain.js"></script>\n\1\2',
            html,
            count=1,
            flags=re.IGNORECASE,
        )
        if n == 0:
            # Fallback: append before </body>
            html = re.sub(
                r"</body>",
                '  <script src="domain.js"></script>\n'
                '  <script src="js/flutter_bootstrap.js" async></script>\n</body>',
                html,
                count=1,
                flags=re.IGNORECASE,
            )
    index.write_text(html, encoding="utf-8")


def patch_bootstrap(boot: Path) -> None:
    text = boot.read_text(encoding="utf-8")
    m = re.search(r'serviceWorkerVersion:\s*"([^"]*)"', text)
    ver = m.group(1) if m else ""

    new_load = (
        "_flutter.loader.load({\n"
        "  config: {\n"
        '    entrypointBaseUrl: "js/"\n'
        "  },\n"
        "  serviceWorkerSettings: {\n"
        f'    serviceWorkerVersion: "{ver}",\n'
        f'    serviceWorkerUrl: "js/flutter_service_worker.js?v={ver}"\n'
        "  }\n"
        "});"
    )

    text2, n = re.subn(
        r"_flutter\.loader\.load\(\s*\{[\s\S]*?\}\s*\);",
        new_load,
        text,
        count=1,
    )
    if n == 0:
        print("WARN: could not patch _flutter.loader.load in", boot, file=sys.stderr)
        return
    boot.write_text(text2, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("public_web_dir")
    ap.add_argument("api_base_url")
    args = ap.parse_args()

    root = Path(args.public_web_dir).resolve()
    api = args.api_base_url
    if not root.is_dir():
        print(f"error: not a directory: {root}", file=sys.stderr)
        return 1
    index = root / "index.html"
    if not index.is_file():
        print(f"error: missing {index}", file=sys.stderr)
        return 1

    js_dir = root / "js"
    js_dir.mkdir(exist_ok=True)

    moved: list[str] = []
    for p in sorted(root.glob("*.js")):
        if p.name == "domain.js":
            continue
        dest = js_dir / p.name
        if dest.exists():
            dest.unlink()
        shutil.move(str(p), str(dest))
        moved.append(p.name)

    domain = root / "domain.js"
    domain.write_text(
        "// LOONGS Admin — API base URL (edit without rebuilding Flutter).\n"
        "// Supports {host} → browser hostname on web.\n"
        f"window.__LOONGS_API_BASE_URL__ = {_js_string_literal(api)};\n",
        encoding="utf-8",
    )

    patch_index(index)

    boot = js_dir / "flutter_bootstrap.js"
    if boot.is_file():
        patch_bootstrap(boot)
    else:
        print("WARN: missing", boot, file=sys.stderr)

    print(
        f"OK reorganize_web_js: moved {len(moved)} root *.js -> js/, "
        f"wrote domain.js, patched index.html + bootstrap"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
