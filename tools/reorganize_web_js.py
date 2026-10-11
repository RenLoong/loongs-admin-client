#!/usr/bin/env python3
"""Post-process Flutter web build output.

Moves root-level *.js into js/, renames index.html → spa.html (so
ServeAppPublicMiddleware cannot serve an uninjected shell), patches
js/flutter_bootstrap.js so the loader finds entrypoint + service worker
under js/, and inserts <!--LOONGS_API_BASE_INJECT--> for ClientEntry.

API base URL is injected at request time by admin server ClientEntry
(from OAUTH_ALLOWED_ORIGINS); this script does NOT write domain.js.

Usage:
  python3 tools/reorganize_web_js.py <public_web_dir> [api_base_url_ignored]
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

INJECT_MARKER = "<!--LOONGS_API_BASE_INJECT-->"


def patch_spa(spa: Path) -> None:
    html = spa.read_text(encoding="utf-8")
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
    # Ensure inject marker immediately before bootstrap (ClientEntry replaces it).
    if INJECT_MARKER not in html:
        html, n = re.subn(
            r"([ \t]*)(<script\s+[^>]*src=[\"']js/flutter_bootstrap\.js[\"'][^>]*>\s*</script>)",
            rf"\1{INJECT_MARKER}\n\1\2",
            html,
            count=1,
            flags=re.IGNORECASE,
        )
        if n == 0:
            html = re.sub(
                r"</body>",
                f"  {INJECT_MARKER}\n"
                '  <script src="js/flutter_bootstrap.js" async></script>\n</body>',
                html,
                count=1,
                flags=re.IGNORECASE,
            )
    spa.write_text(html, encoding="utf-8")


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
    ap.add_argument(
        "api_base_url",
        nargs="?",
        default="",
        help="Ignored (API base is injected by ClientEntry from OAUTH_ALLOWED_ORIGINS).",
    )
    args = ap.parse_args()

    root = Path(args.public_web_dir).resolve()
    if not root.is_dir():
        print(f"error: not a directory: {root}", file=sys.stderr)
        return 1

    index = root / "index.html"
    spa = root / "spa.html"
    if index.is_file():
        if spa.exists():
            spa.unlink()
        index.rename(spa)
    elif not spa.is_file():
        print(f"error: missing {index} and {spa}", file=sys.stderr)
        return 1

    # Remove legacy domain.js if present.
    domain = root / "domain.js"
    if domain.is_file():
        domain.unlink()

    js_dir = root / "js"
    js_dir.mkdir(exist_ok=True)

    moved: list[str] = []
    for p in sorted(root.glob("*.js")):
        dest = js_dir / p.name
        if dest.exists():
            dest.unlink()
        shutil.move(str(p), str(dest))
        moved.append(p.name)

    patch_spa(spa)

    boot = js_dir / "flutter_bootstrap.js"
    if boot.is_file():
        patch_bootstrap(boot)
    else:
        print("WARN: missing", boot, file=sys.stderr)

    print(
        f"OK reorganize_web_js: moved {len(moved)} root *.js -> js/, "
        f"spa.html ready (no domain.js; ClientEntry injects API base)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
