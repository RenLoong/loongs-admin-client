#!/usr/bin/env bash
# Linux / WSL pack for LOONGS Admin PC (run from admin/client).
# Builds: web + linux only. Uses native Linux `fvm` + .fvmrc (no auto-install).
# Windows → .\pack.ps1   |   macOS → ./pack.command
#
#   ./pack.sh
#   ./pack.sh --skip-web
#   ./pack.sh --linux
#   ./pack.sh --skip-web --linux

set -euo pipefail

SKIP_WEB=0
DO_LINUX=0
# NOTE: do not write ${VAR:-http://{host}:21000} — bash ends the default at the first '}'
# which corrupts it to http://{host:21000}.
_DEFAULT_API_BASE_URL='http://{host}:21000'
API_BASE_URL="${API_BASE_URL:-$_DEFAULT_API_BASE_URL}"
BASE_HREF="${BASE_HREF:-/admin/web/}"

die() { echo "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-web) SKIP_WEB=1; shift ;;
    --linux) DO_LINUX=1; shift ;;
    --skip-linux) DO_LINUX=0; shift ;;
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --base-href) BASE_HREF="$2"; shift 2 ;;
    --windows|--skip-windows|-SkipWindows)
      die "Windows 请在 Windows 上执行: .\\pack.ps1（本脚本 pack.sh 只构建 web / linux）"
      ;;
    --macos|--osx|--skip-macos)
      die "macOS 请在 macOS 上执行: ./pack.command（本脚本 pack.sh 只构建 web / linux）"
      ;;
    --flutter-version)
      die "不要传 --flutter-version；请在 .fvmrc 中固定版本"
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

CLIENT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_WEB="$CLIENT_ROOT/../server/apps/Admin/public/web"
DIST_DIR="$CLIENT_ROOT/dist"

step() { printf '\n==> %s\n' "$*"; }

# Refuse Windows fvm.exe wrappers (common leftover from older pack.sh).
resolve_linux_fvm() {
  local cand
  for cand in "$(command -v fvm 2>/dev/null || true)" /usr/local/bin/fvm "$HOME/.pub-cache/bin/fvm"; do
    [[ -n "$cand" && -x "$cand" ]] || continue
    if head -c 200 "$cand" 2>/dev/null | grep -qE 'fvm\.exe|/mnt/[a-z]/fvm'; then
      continue
    fi
    if file -b "$cand" 2>/dev/null | grep -qiE 'PE32|MS-DOS|Windows'; then
      continue
    fi
    # shell wrapper that only execs .exe
    if head -5 "$cand" 2>/dev/null | grep -q 'fvm\.exe'; then
      continue
    fi
    printf '%s\n' "$cand"
    return 0
  done
  return 1
}

FVM_BIN="$(resolve_linux_fvm || true)"
if [[ -z "${FVM_BIN:-}" ]]; then
  cat >&2 <<'MSG'
未找到 Linux 版 fvm（当前 PATH 上的 fvm 若是 exec …/fvm.exe 的包装脚本，不能用于本脚本）。

请安装 Linux 版 fvm，例如:
  dart pub global activate fvm
  # 或 https://fvm.app/documentation/getting-started/installation

若 /usr/local/bin/fvm 是 Windows 包装，请删掉或移走后再装 Linux 版。
Windows 桌面包请用: .\pack.ps1
macOS 桌面包请用: ./pack.command
MSG
  exit 127
fi

echo "fvm=$FVM_BIN $($FVM_BIN --version 2>/dev/null || true)"

[[ -f "$CLIENT_ROOT/.fvmrc" ]] || die "缺少 .fvmrc，请先固定 Flutter 版本"
PINNED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flutter"])' "$CLIENT_ROOT/.fvmrc")"
echo ".fvmrc flutter=$PINNED"

cd "$CLIENT_ROOT"

step "fvm use .fvmrc ($PINNED) — no auto-install"
SDK_OK=0
CACHE_ROOT="${FVM_CACHE_PATH:-/opt/fvm}"
for d in \
  "$CACHE_ROOT/versions/$PINNED" \
  "$HOME/fvm/versions/$PINNED" \
  "$HOME/.fvm/versions/$PINNED" \
  "/opt/fvm/versions/$PINNED"
do
  if [[ -x "$d/bin/flutter" ]]; then SDK_OK=1; echo "SDK=$d"; break; fi
done
if [[ "$SDK_OK" -eq 0 ]]; then
  die "Flutter $PINNED 未安装，打包已中断。
请先手动安装: fvm install $PINNED
查看已安装版本: fvm list"
fi

"$FVM_BIN" use "$PINNED" --force
"$FVM_BIN" flutter --version

if [[ "$SKIP_WEB" -eq 0 ]]; then
  step "fvm flutter build web"
  "$FVM_BIN" flutter pub get
  "$FVM_BIN" flutter build web --release --base-href "$BASE_HREF" --dart-define="API_BASE_URL=$API_BASE_URL"
  test -f build/web/index.html
  step "Copy build/web -> $PUBLIC_WEB"
  mkdir -p "$PUBLIC_WEB"
  find "$PUBLIC_WEB" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a build/web/. "$PUBLIC_WEB"/
  if [[ -f "$CLIENT_ROOT/tools/fix_geist_font_names.py" ]]; then
    python3 "$CLIENT_ROOT/tools/fix_geist_font_names.py" \
      "$CLIENT_ROOT/build/web/assets" \
      "$PUBLIC_WEB/assets" || true
  fi
  echo "OK public/web"
else
  echo "Skip web"
fi

if [[ "$DO_LINUX" -eq 1 ]]; then
  step "fvm flutter build linux"
  "$FVM_BIN" flutter pub get
  "$FVM_BIN" flutter build linux --release
  RELEASE=""
  for c in \
    "$CLIENT_ROOT/build/linux/x64/release/bundle" \
    "$CLIENT_ROOT/build/linux/release/bundle"
  do
    [[ -d "$c" ]] && RELEASE="$c" && break
  done
  [[ -n "$RELEASE" ]] || die "linux release bundle 未找到"
  mkdir -p "$DIST_DIR"
  ZIP="$DIST_DIR/admin-pc-linux.zip"
  rm -f "$ZIP"
  step "Zip -> $ZIP"
  (cd "$RELEASE" && zip -r -q "$ZIP" .)
  echo "OK $ZIP"
else
  echo "Skip linux（需要时加 --linux）"
fi

printf '\nDone (Linux pack.sh, .fvmrc=%s).\n' "$PINNED"
