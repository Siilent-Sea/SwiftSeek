#!/usr/bin/env bash
# SwiftSeek K2 + N2 — repeatable .app packaging.
#
# Usage:
#   ./scripts/package-app.sh                 # default: no-Dock / menu bar agent (LSUIElement=true)
#   ./scripts/package-app.sh --dock-app      # opt-in: ordinary Dock app (LSUIElement=false)
#   ./scripts/package-app.sh --sandbox       # restricted env (HOME +
#                                             CLANG_MODULE_CACHE_PATH already
#                                             set by the caller); combinable
#   ./scripts/package-app.sh --no-sign       # skip codesign (quick iter)
#
# What it does (fresh-clone safe):
#   1. swift build -c release
#   2. lay out dist/SwiftSeek.app/Contents/{MacOS,Resources}
#   3. copy .build/release/SwiftSeek into Contents/MacOS/
#   4. generate AppIcon.icns via scripts/make-icon.swift (no iconutil)
#   5. write Info.plist with version + GitCommit + BuildDate + LSUIElement
#      (per N2 mode); K1's BuildInfo accessor reads identity at runtime
#   6. ad-hoc codesign the bundle
#   7. self-verify: codesign -dv, plutil -lint, file structure
#
# N2 (everything-dockless-hardening): the default mode is now no-Dock. The
# bundled Info.plist writes LSUIElement=true so macOS Launch Services keeps
# SwiftSeek out of the Dock and the global app switcher even before the
# AppKit runtime gets a chance to call NSApp.setActivationPolicy(.accessory).
# The runtime path stays in place — the user-facing Dock-visible setting in
# 设置 → 常规 still flips between .accessory and .regular at launch — so a
# user who opted in via dock_icon_visible=1 gets a Dock icon despite
# LSUIElement=true (the runtime override wins for an already-launched
# process). When you genuinely want a Dock-first build (mostly for QA of the
# Dock-visible code path), pass --dock-app to flip LSUIElement=false; that
# matches the historical L1/L2 packaging.
#
# Non-goals (left to later N / K stages or out of scope):
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
# N2: package mode controls Info.plist LSUIElement.
#   "agent"    = default no-Dock build, LSUIElement=true
#   "dock_app" = opt-in Dock-visible build, LSUIElement=false
package_mode="agent"
for arg in "$@"; do
    case "$arg" in
        --sandbox) sandbox_flag="--disable-sandbox" ;;
        --no-sign) do_sign=0 ;;
        --dock-app) package_mode="dock_app" ;;
        --no-dock|--agent) package_mode="agent" ;;  # explicit alias for clarity in scripts / CI
        -h|--help)
            sed -n '2,46p' "$0"
            exit 0
            ;;
        *)
            echo "[package-app.sh] unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

# Resolve mode → human label + LSUIElement plist value.
case "$package_mode" in
    agent)
        DOCK_MODE_LABEL="no-Dock / menu bar agent (default)"
        LS_UI_ELEMENT_VALUE="<true/>"
        LS_UI_ELEMENT_HUMAN="true"
        ;;
    dock_app)
        DOCK_MODE_LABEL="Dock app (opt-in via --dock-app)"
        LS_UI_ELEMENT_VALUE="<false/>"
        LS_UI_ELEMENT_HUMAN="false"
        ;;
    *)
        echo "[package-app.sh] internal error: unknown package_mode=$package_mode" >&2
        exit 3
        ;;
esac

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# --- versioning -------------------------------------------------------
APP_VERSION="${SWIFTSEEK_APP_VERSION:-1.0-K2}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
BUILD_DATE="$(date '+%Y-%m-%d')"
BUNDLE_ID="${SWIFTSEEK_BUNDLE_ID:-com.local.swiftseek}"

# N2: print the full intent banner before any work so a Console paste of
# the package log immediately identifies the package mode + plist value.
echo "[package-app.sh] N2 mode=$package_mode ($DOCK_MODE_LABEL)"
echo "[package-app.sh] LSUIElement=$LS_UI_ELEMENT_HUMAN"
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
# K2 round 3: assemble .icns directly via make-icon.swift's --icns
# output, bypassing `iconutil`. iconutil's strict iconset validator
# was rejecting our generated iconset on Codex's macOS / iconutil
# build (rounds 1-2) even after PNG pixel-dim correctness fixes.
# The .icns binary format is documented; make-icon.swift now writes
# it directly with all 10 standard PNG entries (ic04–ic14).
echo "[package-app.sh] generate iconset + .icns directly (no iconutil)"
work_tmp="$(mktemp -d -t swiftseek-pkg)"
iconset_dir="$work_tmp/AppIcon.iconset"
mkdir -p "$iconset_dir"
swift "$repo_root/scripts/make-icon.swift" "$iconset_dir" \
    --icns "$app/Contents/Resources/AppIcon.icns" >/dev/null

# Verify the iconset PNGs still match dimension declarations even
# though we no longer feed them to iconutil — caught any future
# regression in make-icon.swift's render path.
echo "[package-app.sh] verify iconset PNG dimensions (defensive)"
icon_fail=0
for png in "$iconset_dir"/icon_*.png; do
    fname="$(basename "$png")"
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
    echo "[package-app.sh] iconset pixel dimensions invalid; aborting before bundle finalize" >&2
    rm -rf "$work_tmp"
    exit 1
fi

# Verify the resulting .icns at least has the magic header + non-zero size.
icns="$app/Contents/Resources/AppIcon.icns"
if [[ ! -f "$icns" ]]; then
    echo "[package-app.sh] AppIcon.icns missing after make-icon.swift" >&2
    rm -rf "$work_tmp"
    exit 1
fi
icns_magic="$(head -c 4 "$icns" 2>/dev/null)"
if [[ "$icns_magic" != "icns" ]]; then
    echo "[package-app.sh] AppIcon.icns magic header bad: '$icns_magic' (expected 'icns')" >&2
    rm -rf "$work_tmp"
    exit 1
fi
icns_bytes="$(stat -f%z "$icns")"
echo "[package-app.sh] AppIcon.icns OK: $icns_bytes bytes"
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
    <!-- N2 (everything-dockless-hardening): LSUIElement is set per package
         mode. Default (no-Dock / menu bar agent) writes <true/>; opt-in
         --dock-app writes <false/>. The runtime AppDelegate path still
         applies activation policy from the dock_icon_visible setting, so
         an existing user who opted into a Dock icon still gets one. -->
    <key>LSUIElement</key>$LS_UI_ELEMENT_VALUE
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
plutil -p "$app/Contents/Info.plist" | grep -E "CFBundleShortVersionString|GitCommit|BuildDate|CFBundleIdentifier|CFBundleIconFile|LSUIElement" | sed 's/^/  /'
# N2: assert the plist actually carries the LSUIElement value matching
# the requested mode. plutil -p formats Bool as the literal word "true"
# or "false" (e.g. `"LSUIElement" => true`), so we match against that.
if ! plutil -p "$app/Contents/Info.plist" | grep -qE "\"LSUIElement\" => $LS_UI_ELEMENT_HUMAN\$"; then
    echo "[package-app.sh] LSUIElement mismatch: expected $LS_UI_ELEMENT_HUMAN for mode=$package_mode" >&2
    plutil -p "$app/Contents/Info.plist" | grep LSUIElement >&2 || true
    exit 4
fi
echo "[package-app.sh] LSUIElement assertion OK (=$LS_UI_ELEMENT_HUMAN, mode=$package_mode)"
if [[ "$do_sign" == "1" ]]; then
    echo "[package-app.sh] codesign -dv:"
    codesign -dv --verbose=2 "$app" 2>&1 | sed 's/^/  /'
fi

echo ""
echo "[package-app.sh] === done ==="
echo "[package-app.sh] mode: $package_mode ($DOCK_MODE_LABEL)"
echo "[package-app.sh] LSUIElement: $LS_UI_ELEMENT_HUMAN"
echo "[package-app.sh] commit: $GIT_COMMIT"
echo "[package-app.sh] bundle id: $BUNDLE_ID"
echo "[package-app.sh] bundle: $app"
echo "[package-app.sh] launch: open $app"
echo "[package-app.sh] confirm build identity:"
echo "  - About → 顶部 summary 应显示 'SwiftSeek $APP_VERSION commit=$GIT_COMMIT build=$BUILD_DATE'"
echo "  - 启动日志（Console.app 过滤 SwiftSeek）应有同样三连，并显示 'Dock — Info.plist LSUIElement=$LS_UI_ELEMENT_HUMAN; …'"
if [[ "$package_mode" == "agent" ]]; then
    echo "  - 默认 (no-Dock) 包：Dock 中应不出现 SwiftSeek；菜单栏图标应出现"
    echo "  - 如果当前 DB 中 dock_icon_visible=1，runtime 仍会把 activation policy 提到 .regular，Dock 会出现；这是用户设置导致，不是包体回归（详见 N3）"
else
    echo "  - --dock-app 包：Dock 中应出现 SwiftSeek 图标；菜单栏入口仍保留"
fi
