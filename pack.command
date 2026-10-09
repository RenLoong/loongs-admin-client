#!/bin/bash
# macOS pack for LOONGS Admin PC (double-click or run from admin/client).
# Builds: web + macos only. Uses macOS `fvm` + .fvmrc (no auto-install).
# Linux/WSL → ./pack.sh   |   Windows → .\pack.ps1
#
#   ./pack.command
#   ./pack.command --skip-web
#   ./pack.command --skip-macos

cd "$(dirname "$0")" || exit 1
set -euo pipefail

SKIP_WEB=0
SKIP_MACOS=0
# NOTE: do not write ${VAR:-http://{host}:21000} — bash ends the default at the first '}'
# which corrupts it to http://{host:21000}.
_DEFAULT_API_BASE_URL='http://{host}:21000'
API_BASE_URL="${API_BASE_URL:-$_DEFAULT_API_BASE_URL}"
BASE_HREF="${BASE_HREF:-/admin/web/}"

die() { echo "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-web) SKIP_WEB=1; shift ;;
    --skip-macos) SKIP_MACOS=1; shift ;;
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --base-href) BASE_HREF="$2"; shift 2 ;;
    --windows|--linux)
      die "请在对应系统执行: Windows → .\\pack.ps1；Linux/WSL → ./pack.sh（本脚本 pack.command 只构建 web / macos）"
      ;;
    --flutter-version)
      die "不要传 --flutter-version；请在 .fvmrc 中固定版本"
      ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

CLIENT_ROOT="$(pwd)"
PUBLIC_WEB="$CLIENT_ROOT/../server/apps/Admin/public/web"
DIST_DIR="$CLIENT_ROOT/dist"

step() { printf '\n==> %s\n' "$*"; }

command -v fvm >/dev/null || die "未找到 macOS fvm，请先安装: https://fvm.app"
echo "fvm=$(command -v fvm) $(fvm --version 2>/dev/null || true)"

[[ -f "$CLIENT_ROOT/.fvmrc" ]] || die "缺少 .fvmrc，请先固定 Flutter 版本"
PINNED="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["flutter"])' "$CLIENT_ROOT/.fvmrc")"
echo ".fvmrc flutter=$PINNED"

step "fvm use .fvmrc ($PINNED) — no auto-install"
SDK_OK=0
for d in \
  "${FVM_CACHE_PATH:-$HOME/fvm}/versions/$PINNED" \
  "$HOME/fvm/versions/$PINNED" \
  "$HOME/Library/Application Support/fvm/versions/$PINNED"
do
  if [[ -x "$d/bin/flutter" ]]; then SDK_OK=1; echo "SDK=$d"; break; fi
done
if [[ "$SDK_OK" -eq 0 ]]; then
  die "Flutter $PINNED 未安装，打包已中断。
请先手动安装: fvm install $PINNED
查看已安装版本: fvm list"
fi

fvm use "$PINNED" --force
fvm flutter --version

if [[ "$SKIP_WEB" -eq 0 ]]; then
  step "fvm flutter build web"
  fvm flutter pub get
  fvm flutter build web --release --base-href "$BASE_HREF" --dart-define="API_BASE_URL=$API_BASE_URL"
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

if [[ "$SKIP_MACOS" -eq 0 ]]; then
  step "fvm flutter build macos"
  fvm flutter pub get
  fvm flutter build macos --release
  APP=""
  for c in \
    "$CLIENT_ROOT/build/macos/Build/Products/Release"/*.app \
    "$CLIENT_ROOT/build/macos/Build/Products/Release"
  do
    # shellcheck disable=SC2086
    for hit in $c; do
      [[ -e "$hit" ]] && APP="$hit" && break 2
    done
  done
  [[ -n "$APP" ]] || die "macos .app 未找到"
  mkdir -p "$DIST_DIR"
  ZIP="$DIST_DIR/admin-pc-macos.zip"
  rm -f "$ZIP"
  step "Zip -> $ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "OK $ZIP"
else
  echo "Skip macos"
fi

printf '\nDone (macOS pack.command, .fvmrc=%s).\n' "$PINNED"
