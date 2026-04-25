# SwiftSeek 安装 / 升级 / 回滚

K4 流程文档。涵盖：本地构建产物如何安装到日常使用位置、升级时如何替换、回滚到旧版本时的数据库 schema 约束、Launch at Login 在未签名 / ad-hoc 构建下的真实边界、stale bundle / 多实例风险及排查路径。

> 当前所有路径都是**未签名 / 未公证**本地交付。Apple Developer ID 签名、notarization、DMG、auto updater 都不在 SwiftSeek 当前轨道范围。

---

## 安装

### 一条命令打包 + 启动

```bash
git clone <repo> && cd SwiftSeek
./scripts/package-app.sh
open dist/SwiftSeek.app
```

`scripts/package-app.sh` 自动完成：
1. `swift build -c release`
2. 创建 `dist/SwiftSeek.app/Contents/{MacOS,Resources}` 完整结构
3. `Sources/SwiftSeekCore/Diagnostics.swift` 等模块编译进 binary
4. `scripts/make-icon.swift --icns` 直接生成 `AppIcon.icns`（不依赖 `iconutil`）
5. 写 `Info.plist`，自动注入：
   - `CFBundleShortVersionString`（默认 `1.0-K2+`，用 `SWIFTSEEK_APP_VERSION=...` 覆盖）
   - `GitCommit`（自动 `git rev-parse --short HEAD`）
   - `BuildDate`（自动当天日期）
   - `CFBundleIdentifier`（默认 `com.local.swiftseek`，用 `SWIFTSEEK_BUNDLE_ID=...` 覆盖）
6. ad-hoc `codesign`
7. 自检：`plutil -lint` / `codesign -dv` / 文件结构 / `.icns` magic

### 放到日常使用位置

推荐 `/Applications/`（Spotlight / Launchpad / Finder 默认查找位置）：

```bash
# 第一次安装
cp -R dist/SwiftSeek.app /Applications/
```

或保留在仓库目录运行（开发迭代场景）：

```bash
open dist/SwiftSeek.app
```

### 首次打开 / Gatekeeper

未签名 / 未公证应用首次打开会被 Gatekeeper 拦截，提示 "无法验证开发者" 或 "已损坏"。处理：

1. **Finder 右键 → 打开** → 弹窗点 "打开"（系统记下许可，下次双击正常）。
2. 或 **系统设置 → 隐私与安全性** → 滚到底找 "已阻止 SwiftSeek 打开" → 点 "仍要打开"。
3. **CLI 备用**（绕过 Finder）：`open /Applications/SwiftSeek.app` 走 LaunchServices，通常不触发 Gatekeeper UI。

如果系统抹掉了 quarantine 后仍被 ad-hoc 拒绝，运行 `xattr -dr com.apple.quarantine /Applications/SwiftSeek.app` 强删 quarantine 标记（仅自己生成的 app 安全这么做）。

---

## 升级

### 步骤

1. **退出旧 SwiftSeek**：
   - Dock 右键 → 退出
   - 或菜单栏图标 → 退出 SwiftSeek
   - 或 `pkill -f "SwiftSeek.app"`
2. **重新打包新版本**：
   ```bash
   git pull
   ./scripts/package-app.sh
   ```
3. **替换**：
   ```bash
   rm -rf /Applications/SwiftSeek.app
   cp -R dist/SwiftSeek.app /Applications/
   ```
4. **启动并核对 build identity**：
   - `open /Applications/SwiftSeek.app`
   - 设置 → 关于 → 顶部 summary 应显示新的 `commit=<新 hash>`
   - Console.app 过滤 SwiftSeek，启动头三行 `SwiftSeek: SwiftSeek <ver> commit=<新 hash> build=<日期>` / `bundle=` / `binary=` 应反映新 bundle 路径
   - 如果 commit 和你刚 pull 的 `git rev-parse --short HEAD` 不一致 → 替换失败或还在跑老进程

### 替换失败常见原因

- 旧 SwiftSeek 没退干净（FSEvents / hotkey 仍在监听）
  - 解决：`pgrep -fl SwiftSeek` 看是否还有进程；`pkill -9 -f SwiftSeek` 强杀
- macOS LaunchServices 缓存旧 bundle path
  - 解决：`/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f /Applications/SwiftSeek.app`，再 `killall Dock` 让 Dock 刷图标
- `cp -R` 没把 bundle 全部覆盖（旧文件残留）
  - 解决：先 `rm -rf` 再 `cp -R`，不要用 `cp -Rn`

---

## 回滚

### 操作步骤

1. **保留旧 app**：升级前不要直接删，先重命名：
   ```bash
   mv /Applications/SwiftSeek.app /Applications/SwiftSeek-K2.app
   cp -R dist/SwiftSeek.app /Applications/  # 新版本
   ```
2. **回滚**：
   ```bash
   pkill -f SwiftSeek
   rm -rf /Applications/SwiftSeek.app
   mv /Applications/SwiftSeek-K2.app /Applications/SwiftSeek.app
   open /Applications/SwiftSeek.app
   ```
3. About 中的 commit 应回到旧 hash。

### Schema 兼容约束（必读）

SwiftSeek 数据库 schema 一直在演进：

| Schema | 引入轨道 | 关键表 |
|--------|----------|--------|
| v1 | `v1-baseline` | `files` `meta` `roots` `excludes` |
| v2 | `v1-baseline` | + `file_grams`、`path_lower` |
| v3 | `v1-baseline` | + `settings` |
| v4 | `everything-performance` F1 | + `file_bigrams` |
| v5 | `everything-footprint` G3 | + `file_name_grams` `file_name_bigrams` `file_path_segments` `migration_progress` |
| v6 | `everything-usage` H1 | + `file_usage` |
| v7 | `everything-usage` H2 | + `query_history` `saved_filters` |

**`Database.migrate()` 永远向前，不向后**。一旦 DB 升到 v7，旧 v6 binary 打开时会看到 `PRAGMA user_version=7`，因为有它不认识的表（`query_history` / `saved_filters`），行为未定义（可能崩、可能忽略未知表）。

**回滚原则**：
- 默认 DB 路径 `~/Library/Application Support/SwiftSeek/index.sqlite3`。
- 回滚二进制前**先备份当前 DB**：
  ```bash
  cp ~/Library/Application\ Support/SwiftSeek/index.sqlite3{,.bak-$(date +%Y%m%d)}
  ```
- 如果旧 binary 启动报错或行为异常，删除 DB（或重命名）让旧 binary 自己重建：
  ```bash
  mv ~/Library/Application\ Support/SwiftSeek/index.sqlite3 ~/Library/Application\ Support/SwiftSeek/index.sqlite3.from-v7
  open /Applications/SwiftSeek.app  # 重建空 DB
  ```
  代价是丢使用历史 / 搜索历史 / Saved Filters；roots 配置需重建。
- 如果想保留 DB，**保持 forward 升级，不回滚**是最安全的策略。

---

## Launch at Login

设置 → 常规 → 底部 "随 macOS 登录自动启动 SwiftSeek" 复选框使用公开 `SMAppService.mainApp` API（macOS 13+）。

**两面状态**（J6 + K1 落地，K3 进入 Diagnostics）：
- **用户意图**：复选框状态，持久化到 DB `settings.launch_at_login_requested`
- **系统状态**：实时调 `SMAppService.mainApp.status`，显示 `enabled` / `requiresApproval` / `notRegistered` / `notFound`

未签名 / ad-hoc bundle 已知边界：
- 系统设置 → 通用 → 登录项 中可能要求**手动批准** SwiftSeek 才生效
- 部分 macOS 版本对未签名 bundle 直接拒绝注册；UI 会弹 NSAlert 显示真实错误
- 重命名 / 移动 bundle 后系统状态可能与意图不同步，重新勾选一次复选框可重对齐
- 从仓库 `dist/` 直接跑（非 `/Applications`）通常注册不上，因为 macOS 拒绝把临时位置当登录项

---

## 多实例 / Stale Bundle 风险

### 风险来源

- 同一台机器可能同时存在：
  - 仓库根 `dist/SwiftSeek.app`（K2 产物）
  - `/Applications/SwiftSeek.app`（用户安装）
  - `~/Downloads/SwiftSeek.app`（同事丢过来的旧拷贝）
  - `.build/release/SwiftSeek`（裸二进制）
- 它们共享同一个 DB（默认 `~/Library/Application Support/SwiftSeek/index.sqlite3`）
- SQLite WAL 允许多 reader 但 writer 串行；两个 SwiftSeek 同时跑写操作会被 SQLite busy 错误拒绝

### 自检 stale build

每次启动 SwiftSeek 在 Console.app 看到的头三行：

```
SwiftSeek: SwiftSeek <ver> commit=<hash> build=<date>
SwiftSeek: bundle=<bundle 路径>
SwiftSeek: binary=<binary 路径>
```

或设置 → 关于 → 顶部 summary + 诊断块的 `bundle:` / `binary:` 行。

**判断方法**：
- `commit` 与你刚刚 `git pull` 拿到的 `git rev-parse --short HEAD` 对比
- `bundle` 与你刚刚 `cp -R` 的目标路径对比
- 不一致 → 有更早 instance 在跑，按上面"替换失败常见原因"排查

### 同时运行多个 SwiftSeek

不推荐。如果非要：
- 用不同的 DB 路径 `--db /path/to/other.sqlite3`（CLI 工具支持；GUI 当前固定默认 path，需要改源码或环境变量）
- 关闭其中一个的 Launch at Login，否则系统每次登录都会复活
- DB 写竞争会让其中一个进程报 "database is locked"

---

## 卸载

```bash
pkill -f SwiftSeek
rm -rf /Applications/SwiftSeek.app
# 数据 / DB：
rm -rf ~/Library/Application\ Support/SwiftSeek
# 偏好：
defaults delete com.local.swiftseek 2>/dev/null
# 登录项：在系统设置 → 通用 → 登录项 中手动移除（如有）
```
