# SwiftSeek 安装 / 升级 / 回滚

> 当前活跃轨道是 `everything-dockless-hardening`。历史 L1/L2 文档说明了 no-Dock 设计，但用户已反馈真实 `.app` 仍可能常驻 Dock。N 轨道完成前，遇到 Dock 常驻应同时检查 `Info.plist` 的 `LSUIElement`、DB 中 `dock_icon_visible`、启动日志和 bundle path，不要只按“默认 no Dock”判断。

K4 流程文档。涵盖：本地构建产物如何安装到日常使用位置、升级时如何替换、回滚到旧版本时的数据库 schema 约束、Launch at Login 在未签名 / ad-hoc 构建下的真实边界、stale bundle / 多实例风险及排查路径。

> 当前所有路径都是**未签名 / 未公证**本地交付。Apple Developer ID 签名、notarization、DMG、auto updater 都不在 SwiftSeek 当前轨道范围。

---

## 安装

### 一条命令打包 + 启动

```bash
git clone <repo> && cd SwiftSeek
./scripts/package-app.sh             # N2 默认：no-Dock / menu bar agent (LSUIElement=true)
open dist/SwiftSeek.app
```

如果你**确实**想要带 Dock 图标的普通 App 包（用于 QA Dock-visible 路径或个人偏好），用：

```bash
./scripts/package-app.sh --dock-app   # opt-in: LSUIElement=false，Dock 出现
```

两种模式都会在打包末尾打印一行：
```
[package-app.sh] mode: agent (no-Dock / menu bar agent (default))
[package-app.sh] LSUIElement: true
```
或：
```
[package-app.sh] mode: dock_app (Dock app (opt-in via --dock-app))
[package-app.sh] LSUIElement: false
```
和对应的 commit / bundle id / app path，便于 release 留痕。

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

## 默认形态：菜单栏常驻工具（L1）

> L1 起，SwiftSeek 默认是**菜单栏常驻工具**（macOS menubar agent），**不**显示 Dock 图标。

### 启动后看到什么

- **没有** Dock 图标
- **菜单栏右上角** 出现放大镜（`NSStatusItem`，模板图标会自动适配明暗主题）
- **悬停**菜单栏图标 → tooltip 显示 5 行快速状态（L3 已落地）：
  - `SwiftSeek <ver> commit=<hash> build=<date>`
  - `索引：<空闲 / 索引中 · N/M roots>`
  - `模式：<Compact / Full path / —>`
  - `roots：<总数 个（启用数 启用[，不健康数 不健康]）/ 暂无 root>`
  - `DB 大小：<人类可读字节数 / —>`
- 左键点菜单栏图标 → 弹出菜单（L3 已增强）：
  - `搜索…` ⌥Space
  - `设置…` ⌘,
  - ─── 只读状态行（disabled，非可点）：
    - `索引：空闲` / `索引中 · N/M roots`
    - `SwiftSeek <ver> commit=<hash> build=<date>`
    - `模式：<Compact / Full path / —>`
    - `roots：<...>`
    - `DB 大小：<...>`
  - `退出 SwiftSeek` ⌘Q
- 状态行每次打开菜单都会刷新（`menuNeedsUpdate`），索引中状态变化也会立即更新 tooltip
- 全局热键 `⌥Space`（默认）随时唤出搜索窗，与菜单栏可见性无关
- 本菜单**不读取**系统全局最近项目 / Finder 历史 / private API；roots 健康判定与 K5 RootHealth 同源

### 实现方式（仅供排查参考）

`AppDelegate.applicationDidFinishLaunching`：
- 第一步先调 `NSApp.setActivationPolicy(.accessory)` 作为 L1 默认
- DB 打开后读 `dock_icon_visible` 设置；为 `true` 时切到 `.regular`，否则保持 `.accessory`
- N2 起 `Info.plist` 的 `LSUIElement` 由 `scripts/package-app.sh` 的包模式控制：
  - 默认 `./scripts/package-app.sh` → `LSUIElement=true`（no-Dock / menu bar agent）
  - 显式 `./scripts/package-app.sh --dock-app` → `LSUIElement=false`（Dock app）
- 即使 plist `LSUIElement=true`，runtime activation policy 仍是真正的控制源；用户在 设置 → 常规 勾选 "在 Dock 显示" 后，下次启动 runtime 会调 `.regular`，Dock 仍会出现 — 这是 N3 / 用户自救路径要解决的事

### L2 让 Dock 图标重新显示

设置 → 常规 → 最下方 "在 Dock 显示 SwiftSeek 图标（菜单栏入口仍保留）" 复选框：

1. **勾选**该复选框 → 复选框右下方 note 会变成"已勾选，但当前进程仍是菜单栏 agent 模式"
2. **退出 SwiftSeek**：菜单栏 → "退出 SwiftSeek"（⌘Q）
3. **重新打开** `dist/SwiftSeek.app` 或 `/Applications/SwiftSeek.app`
4. 这次 Dock 中会出现 SwiftSeek 图标；菜单栏图标同时保留
5. 想关回菜单栏 agent 模式：再次取消勾选 → 退出 → 重新打开

为什么需要重启而不是实时切：
- macOS `NSApp.setActivationPolicy(.regular)` ↔ `.accessory` 在未签名 / ad-hoc bundle 上可能让主菜单、key window、Dock 状态不一致
- 持久化意图 + 重启生效是当前轨道的诚实契约；UI note 会明确告诉用户需要重启
- N2 起默认包写 `LSUIElement=true`；`--dock-app` 包写 `LSUIElement=false`。无论 plist 哪种值，runtime activation policy（由 `dock_icon_visible` 决定）才是真正的控制源

### 退出路径（重要）

L1 隐藏 Dock 后**没有** Dock 右键退出。退出方式（按推荐顺序）：

1. **菜单栏图标 → "退出 SwiftSeek"**（最直观）
2. 设置窗口前置时 → `⌘Q`（菜单栏快捷键）
3. CLI 备用：`pkill -f "SwiftSeek.app"` 或 `pkill -f SwiftSeek`
4. 极端 fallback：Activity Monitor → 选 SwiftSeek 进程 → 强制退出

### 找不到菜单栏图标怎么办

可能原因 + 排查：

| 现象 | 可能原因 | 排查 |
|---|---|---|
| 菜单栏没图标但进程在跑 | 屏幕宽度不够，被其他菜单挤掉 | 退出几个常驻菜单栏 app；或缩短系统时钟显示 |
| 菜单栏没图标且进程没启动 | Gatekeeper 拦截 | Finder 右键 → 打开；或看 Console.app 过滤 SwiftSeek |
| 菜单栏没图标但 `pgrep SwiftSeek` 有结果 | activation policy 未生效 | 看 Console 三连日志；可能旧 stale bundle 在跑（K1 build identity 检查） |
| 双击 app 无任何反应 | `applicationShouldHandleReopen` 命中 | 应弹设置窗口作为 fallback；如未弹说明上轮已 crash 但没退出，强杀重启 |

### 双击 app 已经在跑会怎样

L4 已落地单实例防护。新启动的实例发现已有 SwiftSeek 在跑（同 `CFBundleIdentifier`）会主动退出，不抢菜单栏图标 / 不抢热键 / 不写 DB。具体行为：

1. 新实例先打 K1 build identity NSLog 三连（这样 stale bundle 仍可被识别）
2. 紧接着 NSLog 一行冲突日志，包含两个 bundle path、两个 pid、两个 executable path：
   ```
   SwiftSeek: another instance detected — sibling pid=12345 bundle=/Applications/SwiftSeek.app exec=...; our pid=67890 bundle=/Users/.../dist/SwiftSeek.app exec=...; deferring to sibling and exiting
   ```
3. 新实例调 `NSRunningApplication.activate(options:)` 唤醒旧实例 + 广播 `DistributedNotification` 让旧实例弹设置窗口给视觉反馈
4. 新实例 `NSApp.terminate(nil)` 退出
5. 屏幕上仍只有一个菜单栏图标 + 旧实例的设置窗口前置

适用场景：
- 同一 `.app` 双击两次
- `dist/SwiftSeek.app` 和 `/Applications/SwiftSeek.app` 同时启动（两者默认共享 `com.local.swiftseek` bundle id）
- Launch at Login 与手动启动并发（系统先拉起一份，用户再点一次 → 后启动的那份 deferring）

不在范围：
- 用 `SWIFTSEEK_BUNDLE_ID=...` 自定义不同 bundle id 的两份 build → macOS 视为不同 app，单实例检查不跨触发
- `swift run SwiftSeek`（源码直跑）：`Bundle.main.bundleIdentifier` 为 nil，单实例检查跳过；Console 会有 NSLog 说明
- 跨用户会话（不同 macOS 用户登录）：单实例检查只看当前会话

### 与 K4 升级 / 回滚不冲突

- K4 文档讲的"退出旧 SwiftSeek"路径在 L1 之后等价于"菜单栏 → 退出 SwiftSeek"
- 升级流程仍是 退出 → 重打包 → 替换 bundle → 启动；只是退出方式从 Dock 右键变成菜单栏

---

## 升级

### 步骤

1. **退出旧 SwiftSeek**：
   - 菜单栏图标 → 退出 SwiftSeek（L1 起的主要路径）
   - 或 `pkill -f "SwiftSeek.app"`
   - （Dock 右键退出在 L1 之后不可用，因为 Dock 默认隐藏）
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

## 权限 / Full Disk Access / Root 覆盖（K5）

SwiftSeek 不绕过 macOS 权限模型。一个目录是否能被索引，取决于它对 SwiftSeek 进程是否可读。当一个 root 不能正常索引时，先在 设置 → 索引 的 roots 表里看右侧状态徽标，再决定如何处理。

### 四种状态徽标含义

| 徽标 | 含义 | 典型场景 | 恢复路径 |
|---|---|---|---|
| ✅ 就绪 | 目录可读、已纳入索引 | 普通子目录 | 无需操作 |
| ⏳ 索引中 | 后台正在扫描该 root | 刚 add root / 重建后 | 等扫描完成 |
| ⏸ 已停用 | 用户主动停用了该 root | 设置里点过"启用/停用所选" | 再次点击恢复 |
| 💾 卷未挂载 | 路径前缀是 `/Volumes/<X>`，但 `<X>` 不在 `/Volumes` 下 | 外接盘拔了 / 网络盘掉线 | 接回设备或重连网络 |
| 🔌 路径不存在 | 目录被删 / 移动 / 重命名 | 用户在 Finder 删了该目录 | 移除该 root，或在原位置重建目录 |
| ⚠️ 无访问权限 | 目录存在但当前权限不允许 SwiftSeek 读取 | 缺 Full Disk Access、目录权限是 700 且属于其他用户、TCC 拦截 Desktop/Documents/Downloads | 见下文 FDA 引导 |

把鼠标停在 roots 表的某一行，会弹出**详细原因**（K5 的 RootHealthReport.detail），告诉你当前判定的依据。这条 detail 也会出现在 设置 → 关于 → 复制诊断信息 的输出里，便于贴给协作者排查。

### 给 SwiftSeek 授予 Full Disk Access

一些目录（`~/Desktop` / `~/Documents` / `~/Downloads` / 外接盘 / iCloud / 第三方应用沙盒目录）在未授权前对所有第三方进程都返回 EPERM，外观与"目录不存在"一致但底层是 TCC 拒绝。处理：

1. 设置 → 索引 → 点击底部 **"打开完全磁盘访问设置"** 按钮（K5 新增）
   - 直接跳到 系统设置 → 隐私与安全性 → 完全磁盘访问。
   - 失败时回退到通用隐私面板；仍失败会弹 NSAlert 给出手动路径。
2. 在右侧列表中**加入 `SwiftSeek.app`**（点 `+`，从 `/Applications` 选 `SwiftSeek.app`）。
3. 确认开关**已打开**（绿色）。
4. 回到 SwiftSeek，设置 → 索引 → 点击 **"重新检查权限"** 按钮。
   - 这是 K5 的 recheck / refresh 入口。
   - 它**不重启 app、不动 DB**，只重新读取每个 root 的当前权限并刷新徽标 + tooltip。
5. 如果原来 `⚠️ 无访问权限` 的行变成 `✅ 就绪`，说明授权生效；可手动触发一次 重建索引 让该目录的内容真正进入 DB。

如果某些目录授权后仍是 `⚠️ 无访问权限`：
- 检查目录所有者：`ls -ld <path>`，权限 700 且 owner 不是当前用户时，SwiftSeek 也读不了。
- 通过 系统设置 → 隐私与安全性 → 文件与文件夹 给 SwiftSeek 授权对应类别（Desktop / Documents / Downloads 等）；Full Disk Access 是更高一级的总授权，但部分 macOS 版本两者并行存在。
- 重新登录或重启偶尔可让 TCC 数据库重新生效。

### 外接盘 / 网络盘的边界

- **K5 严格区分**：`💾 卷未挂载` 表示设备不在（路径在 `/Volumes/<X>` 下，但 `<X>` 卷未挂载），与权限不足是两件事。
- 卷重新挂载后，可点 "重新检查权限" 让状态更新；不需要移除 root。
- 网络盘断线表现为 `💾 卷未挂载`（macOS 自动从 `/Volumes` 移除挂载点）。
- 网络盘 / 云盘的实时一致性 SwiftSeek 不承诺，详见 `docs/known_issues.md`。

### Diagnostics 同步显示

设置 → 关于 → 复制诊断信息（或 `Diagnostics.snapshot`）输出里 K5 增加 `roots 健康（K5）：` 段：
```
roots 健康（K5）：
  ✅ 就绪  /Users/me/Documents  — 可读且已纳入索引
  💾 卷未挂载  /Volumes/MyDrive/photos  — 卷 /Volumes/MyDrive 当前未挂载
  ⚠️ 无访问权限  /Users/me/Desktop  — 目录存在但当前权限不允许读取（可能需要 Full Disk Access）
```
最多列 20 个 root，超出时显示总数。bug-report 模板（`docs/manual_test.md` §33u）保持不变，直接复制即可。

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
