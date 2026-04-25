# SwiftSeek vX.Y.Z Release Notes（模板）

> 复制本模板后改名 / 提交。每次发布**必须**保留"已知边界"段，不要在 release notes 里夸大交付能力。

## 基本信息

- **版本号**：`vX.Y.Z`（与 `Info.plist` 中 `CFBundleShortVersionString` 一致）
- **发布日期**：YYYY-MM-DD
- **发布类型**：本地 ad-hoc bundle（macOS 13+）
- **Commit**：`<填入 git rev-parse --short HEAD>`
- **构建脚本**：`./scripts/package-app.sh`
- **Release checklist**：本次发布通过 `docs/release_checklist.md` 全部 15 步验证（如有跳项请在下方"已知边界"列出）

## 本次变更

### 新增 / 改进
- TODO

### 修复
- TODO

### 文档 / 内部
- TODO

## 已知边界（不可删除）

本次发布**不**包含以下能力，用户需要这些请等后续版本或自行处理：

### 签名 / 公证
- ❌ 当前是 **ad-hoc codesign**，**不是** Apple Developer ID 签名
- ❌ 没有 notarization
- ✅ 首次启动可能被 Gatekeeper 拦截，处理方式见 `docs/install.md`"首次打开 / Gatekeeper"段

### 分发 / 升级
- ❌ 没有 DMG（直接交付 `dist/SwiftSeek.app` 目录或同等压缩包）
- ❌ 没有 auto updater（Sparkle / built-in updater）
- ❌ 没有正式 `/Applications` 安装器；安装路径见 `docs/install.md`
- ✅ 升级方式：退出 → 重新打包 → 覆盖 `/Applications/SwiftSeek.app`，commit hash 自检

### Launch at Login
- ✅ 用 `SMAppService.mainApp` 公开 API（macOS 13+）
- ⚠️ 未签名 / ad-hoc bundle 在某些 macOS 版本下需要**手动批准**才生效，或直接拒绝注册
- ⚠️ 从仓库 `dist/` 直接跑通常注册不上；安装到 `/Applications/` 提高成功率
- ✅ 设置 → 常规 → 复选框 + 诊断块 双面状态都暴露

### 权限 / Full Disk Access（K5）
- ✅ root 不可访问会显式分类：`💾 卷未挂载` / `🔌 路径不存在` / `⚠️ 无访问权限`
- ✅ 设置 → 索引 → "重新检查权限" 在不重启 app / 不动 DB 的前提下重评估
- ✅ 设置 → 索引 → "打开完全磁盘访问设置" 直接跳到系统面板
- ⚠️ 不绕过 macOS 权限模型；某些目录（Desktop / Documents / Downloads / 外接盘 / iCloud）需要用户手动授权
- ⚠️ 即使加了 FDA，部分 macOS 版本对未签名 bundle 仍有 TCC 二次拦截，详见 `docs/install.md`"权限 / Full Disk Access / Root 覆盖（K5）"

### 外接盘 / 网络盘
- ⚠️ 网络盘 / 云盘的实时一致性**不承诺**
- ✅ 外接盘拔出会显示 `💾 卷未挂载`，重新挂载后 "重新检查权限" 即可恢复
- ❌ 不做 APFS 原始解析

### 搜索能力
- ❌ 不做全文内容搜索 / OCR / AI 语义搜索 / regex
- ❌ 不做 Finder 插件 / Spotlight 替代
- ✅ 文件名 / 路径 / 扩展名 / 隐藏开关 / `recent:` / `frequent:` / wildcard / quote / OR / NOT 已支持

### 多实例 / Stale Bundle
- ⚠️ 同时存在 `dist/SwiftSeek.app` / `/Applications/SwiftSeek.app` / `.build/release/SwiftSeek` 时，可能跑的不是最新代码
- ✅ 自检方式：设置 → 关于 → 顶部 summary 的 commit / bundle / binary 三联，对比 `git rev-parse --short HEAD`

### 数据库 / Schema
- ✅ 当前 schema 版本：v7（query_history / saved_filters）
- ✅ `Database.migrate()` 严格 forward-only
- ⚠️ 回滚到旧 binary 时**必须**先备份 DB；详见 `docs/install.md`"回滚"段

### 平台 / 沙箱
- ❌ 不做 App Store 沙盒适配
- ❌ 不做 Windows / Linux 跨平台
- ❌ 不调用 macOS private API
- ❌ 不读取 macOS 全局启动次数 / 系统隐私数据

## 已知问题

- TODO（如本轮发布有未修但已知的 bug，列在这里；如无则写"无新增"）

## 安装 / 升级

详见 `docs/install.md`：

```bash
# 安装
git clone <repo> && cd SwiftSeek
./scripts/package-app.sh
cp -R dist/SwiftSeek.app /Applications/
open /Applications/SwiftSeek.app

# 升级
pkill -f SwiftSeek
git pull && ./scripts/package-app.sh
cp -R dist/SwiftSeek.app /Applications/
open /Applications/SwiftSeek.app
# 自检：设置 → 关于 → commit hash 与 git rev-parse --short HEAD 一致
```

## 反馈 / Bug Report

复制 `docs/manual_test.md` §33u 的 bug-report 模板，填入：
- 设置 → 关于 → "复制诊断信息" 的完整文本
- 复现步骤
- 期望行为 vs 实际行为

## 致谢

本次发布由当前活跃 contributor 完成。验收由独立 Codex 代理完成。
