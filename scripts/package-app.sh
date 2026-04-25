#!/usr/bin/env bash
# SwiftSeek K2 — repeatable .app packaging.
#
# Usage:
#   ./scripts/package-app.sh              # standard
#   ./scripts/package-app.sh --sandbox    # restricted env (HOME +
#                                          CLANG_MODULE_CACHE_PATH already
#                                          set by the caller)
#   ./scripts/package-app.sh --no-sign    # skip codesign (quick iter)
#
# What it does (fresh-clone safe):
#   1. swift build -c release
#   2. lay out dist/SwiftSeek.app/Contents/{MacOS,Resources}
#   3. copy .build/release/SwiftSeek into Contents/MacOS/
#   4. generate AppIcon.icns via scripts/make-icon.swift + iconutil
#   5. write Info.plist with version + GitCommit + BuildDate (so K1's
#      BuildInfo accessor reads real values at runtime)
#   6. ad-hoc codesign the bundle
#   7. self-verify: codesign -dv, plutil -lint, file structure
#
# Non-goals (left to later K stages or out of scope):
#   * Apple Developer ID signing — needs identity, none provided
#   * notarization — needs Apple ID + altool / notarytool — out of scope
#   * DMG packaging — out of scope
#   * Sparkle / auto-updater — out of scope
#   * /Applications installation — left to user; K4 documents the flow
#
# Exit codes:
#   0    bundle ready at dist/SwiftSeek.app
#   non-0 step name printed before exit; nothing left half-built —
#         dist/ is wiped at start of every run.

set -euo pipefail

sandbox_flag=""
do_sign=1
for arg in "$@"; do
    case "$arg" in
        --sandbox) sandbox_flag="--disable-sandbox" ;;
        --no-sign) do_sign=0 ;;
        -h|--help)
            sed -n '2,32p' "$0"
            exit 0
            ;;
        *)
            echo "[package-app.sh] unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# --- versioning -------------------------------------------------------
APP_VERSION="${SWIFTSEEK_APP_VERSION:-1.0-K2}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
BUILD_DATE="$(date '+%Y-%m-%d')"
BUNDLE_ID="${SWIFTSEEK_BUNDLE_ID:-com.local.swiftseek}"

echo "[package-app.sh] version=$APP_VERSION commit=$GIT_COMMIT build=$BUILD_DATE bundle_id=$BUNDLE_ID"

# --- build ------------------------------------------------------------
echo "[package-app.sh] swift build -c release $sandbox_flag"
swift build -c release $sandbox_flag

bin="$(swift build -c release --show-bin-path $sandbox_flag)/SwiftSeek"
if [[ ! -x "$bin" ]]; then
    echo "[package-app.sh] expected binary not found: $bin" >&2
    exit 1
fi

# --- clean dist/ ------------------------------------------------------
dist_root="$repo_root/dist"
app="$dist_root/SwiftSeek.app"
echo "[package-app.sh] clean $app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

# --- copy binary ------------------------------------------------------
echo "[package-app.sh] copy binary -> $app/Contents/MacOS/SwiftSeek"
cp "$bin" "$app/Contents/MacOS/SwiftSeek"
chmod +x "$app/Contents/MacOS/SwiftSeek"

# --- icon -------------------------------------------------------------
# iconutil requires the input directory name to literally end in
# `.iconset`. mktemp gives us a random suffix, so we work inside it.
echo "[package-app.sh] generate iconset"
work_tmp="$(mktemp -d -t swiftseek-pkg)"
iconset_dir="$work_tmp/AppIcon.iconset"
mkdir -p "$iconset_dir"
swift "$repo_root/scripts/make-icon.swift" "$iconset_dir" >/dev/null

# K2 round 2 verify: every PNG must have pixel dimensions matching
# its filename declaration (icon_NxN.png == NxN px,
# icon_NxN@2x.png == 2N×2N px). iconutil rejects the entire
# iconset on any mismatch with "Invalid Iconset" — round 1 hit
# this on Codex sandbox where lockFocus produced wrong-sized PNGs.
echo "[package-app.sh] verify iconset PNG dimensions"
icon_fail=0
for png in "$iconset_dir"/icon_*.png; do
    fname="$(basename "$png")"
    # Parse expected base size + @2x flag from filename.
    base="$(echo "$fname" | sed -E 's/^icon_([0-9]+)x[0-9]+(@2x)?\.png$/\1/')"
    is_2x=0
    case "$fname" in *@2x.png) is_2x=1 ;; esac
    expected=$base
    [[ "$is_2x" == "1" ]] && expected=$((base * 2))
    actual_w="$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    actual_h="$(sips -g pixelHeight "$png" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    if [[ "$actual_w" != "$expected" || "$actual_h" != "$expected" ]]; then
        echo "[package-app.sh] BAD: $fname declares ${expected}x${expected} but is ${actual_w}x${actual_h}" >&2
        icon_fail=1
    fi
done
if [[ "$icon_fail" == "1" ]]; then
    echo "[package-app.sh] iconset pixel dimensions invalid; iconutil would reject" >&2
    rm -rf "$work_tmp"
    exit 1
fi

echo "[package-app.sh] iconutil -c icns"
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset_dir"
rm -rf "$work_tmp"

# --- Info.plist -------------------------------------------------------
echo "[package-app.sh] write Info.plist"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SwiftSeek</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>SwiftSeek</string>
    <key>CFBundleDisplayName</key><string>SwiftSeek</string>
    <key>CFBundleVersion</key><string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>GitCommit</key><string>$GIT_COMMIT</string>
    <key>BuildDate</key><string>$BUILD_DATE</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><false/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
EOF

# --- codesign (ad-hoc) ------------------------------------------------
if [[ "$do_sign" == "1" ]]; then
    echo "[package-app.sh] codesign --force --deep --sign - $app"
    codesign --force --deep --sign - "$app"
else
    echo "[package-app.sh] --no-sign passed; skipping codesign"
fi

# --- verify -----------------------------------------------------------
echo ""
echo "[package-app.sh] === verify bundle ==="
echo "[package-app.sh] structure:"
find "$app" -maxdepth 4 -type f -o -type d | sort | sed "s|$repo_root/||" | sed 's/^/  /'
echo ""
echo "[package-app.sh] plutil -lint:"
plutil -lint "$app/Contents/Info.plist"
echo "[package-app.sh] plutil -p (key Info.plist fields):"
plutil -p "$app/Contents/Info.plist" | grep -E "CFBundleShortVersionString|GitCommit|BuildDate|CFBundleIdentifier|CFBundleIconFile" | sed 's/^/  /'
if [[ "$do_sign" == "1" ]]; then
    echo "[package-app.sh] codesign -dv:"
    codesign -dv --verbose=2 "$app" 2>&1 | sed 's/^/  /'
fi

echo ""
echo "[package-app.sh] === done ==="
echo "[package-app.sh] bundle: $app"
echo "[package-app.sh] launch: open $app"
echo "[package-app.sh] confirm build identity:"
echo "  - About → 顶部 summary 应显示 'SwiftSeek $APP_VERSION commit=$GIT_COMMIT build=$BUILD_DATE'"
echo "  - 启动日志（Console.app 过滤 SwiftSeek）应有同样三连"
