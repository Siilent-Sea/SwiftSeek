# 下一阶段任务书：K2

当前活跃轨道：`everything-productization`
当前阶段：`K2`
阶段名称：可重复生成 `.app` bundle 的打包流水线

## 交给 Claude 的任务

你现在只做 K2。目标是把 SwiftSeek 从“有源码、有本地 app 痕迹”推进到“fresh clone 后可重复生成 `.app` bundle”。K1 已经完成 build identity 与 settings release gate；K2 不要重复做诊断 UI，也不要提前写 K4-K6 的安装、权限或最终 release 收口。

K2 不做 DMG，不做 notarization，不做 Apple Developer ID 签名，不做 auto updater。

## 必须先审计的代码路径

- `scripts/package-app.sh`（如不存在则新增）
- `Sources/SwiftSeek/App/AppDelegate.swift`
- `Sources/SwiftSeekCore/BuildInfo.swift`
- `scripts/build.sh`
- `scripts/make-icon.swift`
- `.gitignore`
- `README.md`
- `docs/manual_test.md`
- `docs/known_issues.md`

重点确认：
- 当前 bundle 生成链路哪里还是手工的：`Info.plist`、`AppIcon.icns`、binary copy、codesign。
- `BuildInfo` 依赖的键是否能由 package 脚本自动写入。
- `scripts/build.sh` 与新 package 脚本的边界是否清晰。
- `.gitignore` 是否把生成物和模板边界写清。

## 必须做

1. 新增或重写 `scripts/package-app.sh`，一条命令完成：
   - `swift build -c release`
   - 生成 `SwiftSeek.app/Contents/MacOS/SwiftSeek`
   - 写入 `Info.plist`
   - 生成或复制 `AppIcon.icns`
   - 写入 `CFBundleIdentifier`
   - 写入 `CFBundleVersion`
   - 写入 `CFBundleShortVersionString`
   - 写入 `GitCommit`
   - 写入 `BuildDate`
   - 做 ad-hoc codesign
2. 明确输出目录，例如 `dist/SwiftSeek.app`；重复执行时旧产物清理策略要明确。
3. `scripts/build.sh` 要么调用 package 脚本，要么继续只负责 CLI build，但两者边界必须写清。
4. `scripts/make-icon.swift` 接入 package 流程，不允许继续要求手工 `iconutil` 作为主路径。
5. 更新 README / manual test / known issues，说明：
   - 怎样从 fresh clone 生成 `.app`
   - 怎样检查 bundle 结构、Info.plist 和 codesign
   - 当前仍然只是 ad-hoc，本阶段不承诺正式签名 / 公证
6. 保持 K1 的 build identity、settings release gate、J1/J6 生命周期修复不回退。

## 明确不做

- 不做 DMG。
- 不做 notarization。
- 不做 Apple Developer ID 签名。
- 不做 auto updater。
- 不做安装 / 升级 / 回滚文档收口，那是 K4。
- 不做 Full Disk Access / 权限引导，那是 K5。
- 不新增搜索 / ranking / 索引功能。

## 验收标准

1. fresh clone 后一条命令能生成 `.app`。
2. `.app/Contents/MacOS/SwiftSeek` 存在且可执行。
3. `Info.plist` 字段完整，且 `BuildInfo` 读到的字段来自 package 流程而非手工编辑。
4. `AppIcon.icns` 自动生成或复制进 bundle。
5. `codesign -dv --verbose=2` 可见 ad-hoc 签名。
6. `open dist/SwiftSeek.app` 或等价命令可启动。
7. `scripts/build.sh` / `scripts/package-app.sh` / README 的边界一致，不互相打架。

## 必须补的验证

```text
1. shell: package 脚本 fresh 运行一次，确认产物落到预期目录。
2. shell: `plutil -lint` 与 `plutil -p` 检查 Info.plist。
3. shell: `codesign -dv --verbose=2 dist/SwiftSeek.app`。
4. shell: 检查 `Contents/MacOS/SwiftSeek` 与 `Contents/Resources/AppIcon.icns`。
5. GUI: `open dist/SwiftSeek.app` 启动后，About 仍显示正确 build identity。
6. 回归: K1 的设置窗口 reopen / 10x close-show / 20x tab switch 不回退。
```

## 验收后文档

K2 完成后交 Codex 验收。不要自己宣布 PASS。Codex 如果 PASS，会给 K3 任务书；如果 REJECT，按 blocker 修复。
