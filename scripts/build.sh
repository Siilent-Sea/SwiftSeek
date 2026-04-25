#!/usr/bin/env bash
# SwiftSeek 本地交付构建脚本（P6）
#
# 用途：
#   从干净 checkout 构建发布版二进制，跑一遍冒烟与启动检查，
#   再打印运行说明。不做签名 / notarization / .app bundle；
#   这是仓库内真实可执行的"本地交付"路径，不是假打包。
#
# 环境：
#   macOS 13+，Swift 6.x（本机 Xcode 或 CommandLineTools 任一即可）。
#   在 `codex exec` workspace-write 沙箱下运行时需要设置 HOME 与
#   CLANG_MODULE_CACHE_PATH（默认 ~/.cache 在沙箱下不可写）。
#
# 用法：
#   普通开发机：
#     ./scripts/build.sh
#   受限沙箱：
#     HOME=/tmp/swiftseek-home CLANG_MODULE_CACHE_PATH=/tmp/swiftseek-clang-cache \
#         ./scripts/build.sh --sandbox
#
# 产物：
#   .build/release/SwiftSeek           GUI 可执行
#   .build/release/SwiftSeekIndex      CLI 首次/增量索引
#   .build/release/SwiftSeekSearch     CLI 搜索入口
#   .build/release/SwiftSeekStartup    启动检查（非 GUI，适合 headless 验收）
#   .build/release/SwiftSeekSmokeTest  冒烟测试
#
# 退出码：
#   0  build + smoke + startup check 均成功
#   非 0  任一环节失败；stdout 会说明失败的是哪一步

set -euo pipefail

sandbox_flag=""
if [[ "${1:-}" == "--sandbox" ]]; then
    sandbox_flag="--disable-sandbox"
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo "[build.sh] repo=$repo_root"
echo "[build.sh] swift --version"
swift --version

echo ""
echo "[build.sh] swift build -c release $sandbox_flag"
swift build -c release $sandbox_flag

echo ""
echo "[build.sh] smoke test"
swift run -c release $sandbox_flag SwiftSeekSmokeTest

echo ""
echo "[build.sh] startup check (non-GUI)"
tmp_db="/tmp/swiftseek-build-check-$$.sqlite3"
rm -f "$tmp_db"
swift run -c release $sandbox_flag SwiftSeekStartup --db "$tmp_db"
rm -f "$tmp_db"

bin_dir="$repo_root/.build/release"
echo ""
echo "[build.sh] 构建完成。产物位置："
# -L follows the symlink SwiftPM creates at .build/release -> arm64-apple-macosx/release.
find -L "$bin_dir" -maxdepth 1 -type f -perm -111 -name 'SwiftSeek*' 2>/dev/null | sort | sed 's/^/  /'
echo ""
echo "[build.sh] 运行方式："
echo "  GUI：     $bin_dir/SwiftSeek"
echo "  索引：    $bin_dir/SwiftSeekIndex <dir>"
echo "  搜索：    $bin_dir/SwiftSeekSearch <query>"
echo "  启动检查：$bin_dir/SwiftSeekStartup [--db <path>]"
echo ""
echo "[build.sh] GUI 默认 DB 路径："
echo "  ~/Library/Application Support/SwiftSeek/index.sqlite3"
echo "  （首次运行会自动创建并迁移 schema，当前 schema 版本由 Schema.currentVersion 决定，"
echo "   K1 当前为 v7：files / file_grams / file_bigrams / file_name_grams /"
echo "   file_name_bigrams / file_path_segments / migration_progress / file_usage /"
echo "   query_history / saved_filters）"
echo ""
echo "[build.sh] 注意：本脚本只构建 .build/release 下的可执行文件，不打包 .app bundle、"
echo "  不写 Info.plist、不做 codesign / notarization。可重复打包流水线属于 K2 范围。"
