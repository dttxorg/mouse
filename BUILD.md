# Mac Mouse Fix — 付费墙 + 自动更新 移除版 build 指南

本 fork 包含 2 个 patch：

| 改动 | 影响 |
|---|---|
| `FORCE_LICENSED` 编译 flag | 跳过 30 天试用 + Gumroad license 校验，永远显示已激活 |
| `DISABLE_UPDATES` 编译 flag | 编译期移除整个 Sparkle 自动更新路径；`Info.plist` 的 `SUFeedURL` 已重定向到 `127.0.0.1` 兜底 |

源码修改极少，**作者下次发版合并代码时，冲突点只有 `App/AppDelegate.m` 的 `initSparkle` 一段**，可手动解。

---

## 0. 准备工作

确认你的环境：

```bash
xcode-select -p          # 应该是 /Applications/Xcode.app/Contents/Developer
xcodebuild -version      # 建议 Xcode 15+，需要 macOS 11+ SDK
```

需要一个 **Apple ID + 个人 Team**（免费即可），用于 code signing。

---

## 1. 拉代码

```bash
git clone git@github.com:dttxorg/mac-mouse-fix.git
cd mac-mouse-fix
git checkout patch/disable-updates-and-license-wall
```

> 分支名 `patch/disable-updates-and-license-wall` 已包含全部 patch。

初始化子模块（项目用了一个 `mac-mouse-fix-scripts` 子模块）：

```bash
git submodule update --init --recursive
```

---

## 2. 改 bundle id（避免覆盖官方版）

如果想**和官方版共存**（强烈建议），把以下三处 `com.nuebling.mac-mouse-fix` 改成你自己的前缀，比如 `com.dttxorg.mac-mouse-fix`：

- `App/SupportFiles/App.entitlements`（一般没有 bundle id 字符串，看下 `.xcdatamodeld`）
- `Mouse Fix.xcodeproj/project.pbxproj` 里搜 `com.nuebling.mac-mouse-fix` 共 3 处（App、Helper、Helper-SM 三个 target 的 `PRODUCT_BUNDLE_IDENTIFIER`）

简单粗暴：直接在 Xcode 里：

1. 选 `Mac Mouse Fix` target → **Signing & Capabilities** → Bundle Identifier 改成 `com.dttxorg.mac-mouse-fix`
2. 选 `Mac Mouse Fix Helper` target → 同样改
3. 选 `Mac Mouse Fix Helper (SM)` target（如果有）→ 同样改

> Helper 的 bundle id 必须**保持**跟主 App 的相对关系（`com.X.helper` 和 `com.X.helper-sm`），不然 LoginItem 注册会失败。

---

## 3. 加编译 flag（**核心步骤**）

打开项目：

```bash
open "Mouse Fix.xcodeproj"
```

### 方法 A：用本仓库提供的 xcconfig（推荐）

Xcode → **File → Project Settings...**（在弹窗左上角下拉选 Project，不是 Workspace）→ Based on Configuration File → 选 `xcconfig/dttxorg-patch.xcconfig` → 对 **Project** 和 **Workspace** 都设一下，分别覆盖 Debug / Release。

xcconfig 里就两个值：

```xcconfig
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) FORCE_LICENSED
GCC_PREPROCESSOR_DEFINITIONS        = $(inherited) DISABLE_UPDATES=1
```

### 方法 B：手动改 Build Settings

不引入 xcconfig，直接在 Build Settings 面板搜：

| 字段 | target | 值 |
|---|---|---|
| `Swift Active Compilation Conditions` | Mac Mouse Fix | `$(inherited) FORCE_LICENSED` |
| `Other Swift Flags` 的 `-D`（如果有） | Mac Mouse Fix | `FORCE_LICENSED` |
| `Preprocessor Macros` (Apple Clang) | Mac Mouse Fix | `$(inherited) DISABLE_UPDATES=1` |
| 同上 | Mac Mouse Fix Helper | `$(inherited) DISABLE_UPDATES=1` |

> 三个 target（App、Helper、Helper-SM）都加 `DISABLE_UPDATES`，`FORCE_LICENSED` 只加到 App 即可（Helper 里的 `TrialCounter` 和 `License` 代码读 Swift flag 都会被覆盖成 licensed）。

### 方法 C：临时关掉

如果你只想试一下，**先 build 再加 flag 也行**——加完 flag 后必须 **Clean Build Folder**（⇧⌘K）一次才会生效。

---

## 4. 配 code signing

1. 选 `Mac Mouse Fix` target → **Signing & Capabilities** → Team 选你 Apple ID 下的个人 Team
2. 把 **Hardened Runtime** / **App Sandbox** 之类的选项保持默认（项目已经配好 entitlements）
3. Helper target → Signing 也选同一个 Team
4. 项目根目录的 `xcconfig/CodeSign.xcconfig`（如果存在）/ 项目 build settings 里 `CODE_SIGN_STYLE` = Automatic，`DEVELOPMENT_TEAM` 填你的 Team ID（10 位字符串，不是 Apple ID 邮箱）

> Helper 是 LoginItem，**必须**用同一个 Team 签名 + 同一个 bundle id 前缀，否则启动时 helper 进程拉不起来。

---

## 5. Build

```
Product → Clean Build Folder (⇧⌘K)
Product → Build (⌘B)
```

构建产物在 DerivedData（路径见 Xcode → Preferences → Locations）。找到 `Mac Mouse Fix.app`：

```bash
# 一般在类似下面这种路径
open ~/Library/Developer/Xcode/DerivedData/Mac\ Mouse\ Fix-*/Build/Products/Release/
```

如果只想 build 命令行版本（跳过 Xcode UI）：

```bash
xcodebuild -project "Mouse Fix.xcodeproj" \
           -scheme "Mac Mouse Fix" \
           -configuration Release \
           -derivedDataPath build/ \
           CODE_SIGN_IDENTITY="Apple Development" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           build
# 产物：build/Build/Products/Release/Mac Mouse Fix.app
```

> 命令行 build 不签名，**装上会闪退**。要装必须用 Xcode build（带签名）。

---

## 6. 安装 & 首次授权

```bash
# 1. 移动到 Applications
cp -R "build/Build/Products/Release/Mac Mouse Fix.app" /Applications/

# 2. 首次打开
open "/Applications/Mac Mouse Fix.app"
```

首次启动会弹两个授权：

1. **辅助功能（Accessibility）** — 系统设置 → 隐私与安全性 → 辅助功能 → 允许 "Mac Mouse Fix Helper"
2. **后台项目（Background Items）** — 系统设置 → 通用 → 登录项 → 允许

授权完重启 app，**菜单栏应该出现 🖱️ 图标**，设置里能看到 "Activate License" 按钮**消失**或变灰。

---

## 7. 验证 patch 生效

### 7.1 验证 FORCE_LICENSED

打开 app → 切到 **About** 标签 → 顶部应该**没有** "Activate License" / "X days left in your trial" 之类的横幅。

或者看 log：

```bash
log stream --predicate 'process == "Mac Mouse Fix"' --info --debug | grep -i license
```

应看到：

```
GetLicenseState: MFLicenseState(isLicensed: true, freshness: Fresh, licenseTypeInfo: Force)
```

如果是 `NotLicensed` → flag 没生效，clean build 一次。

### 7.2 验证 DISABLE_UPDATES

启动 app 30 秒后：

```bash
log stream --predicate 'process == "Mac Mouse Fix"' --info --debug | grep -i -E "sparkle|updater|update"
```

应看到：

```
Sparkle updater disabled at compile time (DISABLE_UPDATES)
```

并且**没有**任何去 `raw.githubusercontent.com` / `macmousefix.com` 的网络请求：

```bash
# 在 app 运行状态下执行
lsof -p $(pgrep -x "Mac Mouse Fix") | grep -E "TCP.*github|TCP.*macmousefix"
# 应该输出为空
```

菜单栏 **Mac Mouse Fix → Check for Updates...** 项应该变灰或不可点。

---

## 8. 卸载原版（如果之前装过官方版）

装我们的 patch 版前先卸载官方版，否则 bundle id 改了没事，但如果**没**改 bundle id 就会冲突：

```bash
# 推荐用 AppCleaner（项目作者也推荐）
# https://freemacsoft.net/appcleaner/

# 或者手动：
sudo rm -rf "/Applications/Mac Mouse Fix.app"
rm -rf ~/Library/Application\ Support/com.nuebling.mac-mouse-fix
rm -rf ~/Library/Application\ Support/Mac\ Mouse\ Fix
rm -rf ~/Library/Preferences/com.nuebling.mac-mouse-fix.plist
# 重启一次
```

---

## 9. 常见问题

### Q: 装上闪退，看 crash log 是 "killed by Gatekeeper"
A: 第一次运行需要右键 → 打开 → 仍要打开，或者：

```bash
xattr -dr com.apple.quarantine "/Applications/Mac Mouse Fix.app"
```

### Q: Helper 进程起不来，菜单栏图标变 ❌
A: 检查三个 bundle id 前缀是否一致、code signing Team 是否一致。Log 里看 `helper failed to register` 字样基本就是这个原因。

### Q: build 时找不到 Sparkle framework
A: `Frameworks/Sparkle.framework` 在仓库里自带，不需要下载。如果 build 报 missing，检查 `Mouse Fix.xcodeproj` 的 "Frameworks, Libraries, and Embedded Content" 阶段有没有勾 `Sparkle.framework` 且 Code Sign On Copy。

### Q: 想升级到作者的最新版怎么办？
A:

```bash
git remote add upstream https://github.com/noah-nuebling/mac-mouse-fix.git
git fetch upstream
git checkout master
git merge upstream/master
git checkout patch/disable-updates-and-license-wall
git rebase master
# 解 conflict — 一般只会在 AppDelegate.m 的 initSparkle 段有冲突
# 保留我们的 #if DISABLE_UPDATES 包裹即可
```

### Q: 升级时 Sparkle.framework 也得更新吗？
A: 是的。`git submodule update` 之后如果 Sparkle framework 变了，可能需要重新在 Xcode 里 link 一次。

### Q: 不想自己 build 怎么办？
A: 本仓库不提供 build 产物。Sparkle 用了 EdDSA 公钥签名，第三方 build 出来的 `.app` 装到没装过原版的机器上首次启动时 Sparkle 会校验 — 但因为我们把 `SUFeedURL` 改到 `127.0.0.1` 且 `SUPublicEDKey` 清空，**不会**影响正常运行（仅影响 Sparkle 自动 update 流程）。

---

## 10. 协议说明

本 fork 仍然基于 [MMF License](License)。**自己用**完全没问题。

按 MMF License 条款，要**分发**给其他人且**不收费**，必须保留 monetization systems "active and working as intended"。我们的做法是：
- ✅ 保留所有付费代码原样不动
- ✅ 加 2 个 compile flag 让它**对当前 build 失效**
- ❌ 不能**公开发布 .app 安装包**给不特定的人（除非你做了 substantial improvements）

**不要把这个 fork 的 build 产物挂在网上**——自己用 / 给身边朋友编译没事，发出去要小心。
