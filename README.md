# 轻阅读 LiteReader —— iOS 12.5.8 轻量阅读器

> 这不是把安卓版「静读天下」直接转换成 IPA（技术上不可能：dex 字节码、Android 框架、ELF 原生库都无法在 iOS 上运行）。
> 这是一个**按原版功能清单重写的轻量替代品**：只用系统框架（UIKit / PDFKit / WebKit / AVFoundation）+ 一个解压库，
> 功能聚焦、体积小、无联网、无统计，为 iOS 12.0–12.5.8 老设备适配。
>
> 原版功能提取证据与逐项对照见 **[功能对照表.md](功能对照表.md)**。

## 功能

**格式**：TXT（UTF-8 / UTF-16 / GBK 自动识别）、EPUB、PDF、HTML、DOCX、RTF

**书架**：网格/列表、封面缩略图、封面进度条、未读/在读/已读筛选、收藏、四种排序、书名搜索、长按菜单

**阅读**：
- 目录：TXT 自动识别章节（第X章/卷/回/节、序章、楔子、番外、Chapter N），EPUB 读 NCX/nav 真目录，PDF 读内置 outline
- 书签：添加、改名、跳转、左滑删除、清空本书书签
- 高亮与标注：长按选中文字 → 黄/绿/蓝/粉四色高亮、可写备注；高亮列表、跳转、左滑删除、清空、导出分享
- 全文搜索：TXT 全书定位 + 搜索范围（全书 / 只搜未读（向前）/ 只搜已读（向后））+ 上一个/下一个；EPUB 按章搜索
- 翻页：上下滚动 / 左右平移 / 仿真翻页；左右翻页时点左 30% 上一页、点右 30% 下一页
- 音量键翻页：设置里打开后，音量加大/降低键 = 下一页/上一页
- 朗读：系统 TTS，语速可调，自动续读下一章，支持后台播放
- 自动滚屏：速度可调，读完自动下一章
- 进度条拖拽（并显示剩余时间）、点击中央进入沉浸模式
- 5 套主题：日间 / 护眼 / 羊皮纸 / 夜间 / 纯黑；「夜间自动切换主题」
- 字号、行距、页边距、首行缩进字数、字间距、字体（系统/宋体/楷体/黑体/Georgia）
- 亮度滑块、屏幕常亮
- 阅读统计：今日 / 最近 7 天 / 累计 / 连续天数 / 每本书时长 / 书架总数 / 已读完本数 / 阅读速度（字/分钟）
- 护眼提醒：连续阅读超时提醒 + 深夜提醒；启动密码保护

**导入**：应用内「+」从「文件」多选导入；iTunes/Finder 文件共享；其他 App「用轻阅读打开」

## 工程结构

```
ios_reader/
├─ project.yml                       # XcodeGen 工程描述（iOS 12.0，Swift 5）
├─ 功能对照表.md                      # APK 功能提取 + 实现对照
├─ Resources/
│  ├─ Info.plist                     # 文档类型、文件共享、后台音频
│  ├─ LaunchScreen.storyboard
│  └─ Assets.xcassets/AppIcon        # 已生成全套图标
├─ Sources/
│  ├─ App/AppDelegate.swift
│  ├─ Model/
│  │  ├─ Book.swift                  # 书库、格式、收藏
│  │  ├─ Progress.swift              # 进度、书签、统计、阅读计时
│  │  └─ ReaderTheme.swift           # 5 套主题 + 阅读设置
│  ├─ Core/
│  │  ├─ TextDecoder.swift           # 编码识别
│  │  ├─ ChapterParser.swift         # TXT 章节切分 / 分节
│  │  ├─ EPUBParser.swift            # ZIP 解压 + container/OPF/NCX/nav
│  │  ├─ DocumentText.swift          # DOCX / RTF / HTML 取文本
│  │  ├─ FileKey.swift               # 中文书名 → 唯一安全的缓存名
│  │  ├─ CoverCache.swift            # 封面提取/生成/缓存
│  │  ├─ SpeechController.swift      # AVSpeechSynthesizer 封装
│  │  ├─ Highlights.swift            # 高亮/标注存储（Documents/Highlights.json）
│  │  ├─ Reminders.swift             # 夜间自动主题 + 连续阅读/深夜提醒
│  │  └─ AppLock.swift               # 启动密码（本地加盐散列）+ 密码验证页
│  ├─ UI/
│  │  ├─ LibraryViewController.swift # 书架 + 网格 Cell（封面进度条 / 筛选）
│  │  ├─ ReaderChromeView.swift      # 阅读器底部栏（进度条 + 工具栏）
│  │  ├─ ChoiceListViewController.swift # 通用列表（目录/书签/搜索结果）
│  │  ├─ HighlightsViewController.swift # 高亮列表（跳转/删除/清空/导出）
│  │  ├─ WebHighlightSupport.swift   # WKWebView 取选中文本 → 高亮
│  │  ├─ SettingsViewController.swift   # 阅读设置面板
│  │  ├─ StatsViewController.swift      # 阅读统计
│  │  ├─ ReaderNavigationController.swift # 导航栏/状态栏主题
│  │  └─ UIViewController+Reader.swift  # 判断阅读器是否真正退出
│  └─ Reader/
│     ├─ TextReaderViewController.swift # TXT / DOCX / RTF
│     ├─ EPUBReaderViewController.swift # EPUB（WebKit）
│     ├─ PDFReaderViewController.swift  # PDF（PDFKit）
│     └─ WebReaderViewController.swift  # HTML（WebKit）
├─ tools/make_icon.ps1               # 图标生成脚本（可重跑）
└─ .github/workflows/build-ipa.yml   # 云端 macOS 编译未签名 IPA
```

依赖：仅 [`ZIPFoundation`](https://github.com/weichsel/ZIPFoundation) 0.9.16（SPM 自动拉取，用于解压 EPUB/DOCX）。

---

## 方式 A：GitHub Actions 云端编译（无需 Mac，推荐）

1. 注册/登录 GitHub，新建一个**公开仓库**（Public，macOS 编译额度免费）。
2. 把本目录全部文件上传到仓库根目录（网页 “Add file → Upload files”，或解压 `ios_reader.zip` 后整体拖入）。
   注意保留隐藏目录 **`.github/workflows/`**。
3. 仓库 **Actions** 页 → 选择 “Build unsigned IPA” → **Run workflow**。
4. 约 5–10 分钟，构建成功后在该次运行页面底部下载构件 **`LiteReader-unsigned-ipa`**，
   解压得到 `LiteReader-unsigned.ipa`。

工作流使用 `macos-15` + XcodeGen + `CODE_SIGNING_ALLOWED=NO`，产出**未签名 IPA**，正好给越狱设备用。
（会优先选择 Xcode 16.x，保证 iOS 12.0 部署目标兼容。）

> 首次构建如果报编译错误，把 Actions 日志里的 `error:` 行贴回来即可修正。
> 这台 Windows 没有 Xcode/iOS SDK，无法本地编译验证。

## 方式 B：有 Mac 时本地编译

```bash
brew install xcodegen
cd ios_reader
xcodegen generate
open LiteReader.xcodeproj      # 选真机，关闭自动签名后 Cmd+R
```

或直接命令行产出未签名 `.app` / IPA：

```bash
xcodebuild -project LiteReader.xcodeproj -scheme LiteReader \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/LiteReader.app Payload/
zip -qry LiteReader-unsigned.ipa Payload
```

---

## 在越狱的 iOS 12.5.8 设备上安装

适用设备：iPhone 5s / 6 / 6 Plus / 6s / 6s Plus / SE(1)、iPad Air 1/2、iPad mini 2/3/4 等
（iOS 12.5.8 是这些机型的最终版本；iOS 12 只支持 64 位设备）。

### 步骤 1：越狱

- A7–A11 芯片：**checkra1n**（支持 iOS 12.0–14.8）
- 其他情况：**unc0ver / Chimera**（按机型与版本选择）

### 步骤 2：安装必要插件（Cydia / Sileo / Zebra）

- **AppSync Unified**（允许安装未签名/自签应用）  
  源：`https://cydia.akemi.ai/`
- **Filza File Manager**（文件管理与 IPA 安装）

### 步骤 3：安装 IPA

1. 把 `LiteReader-unsigned.ipa` 传到设备（AirDrop、Filza 局域网、Safari 下载、爱思助手/iTools）。
2. 用 **Filza** 找到 IPA → 点击 → **Install**（依赖 AppSync Unified）。
   或终端：`ipainstaller LiteReader-unsigned.ipa`
3. 回桌面即可看到「轻阅读」。

> 若启动被签名拦截：在设备上用 `ldid -S Payload/LiteReader.app/LiteReader` 伪签名后重装；
> 或改用方式 C。

### 方式 C：Sideloadly 签名（不想装 AppSync 时）

Windows 安装 [Sideloadly](https://sideloadly.io/)，连接设备，拖入 IPA，
用自己的 Apple ID 签名安装（免费账号 7 天需重签，付费开发者账号 1 年）。
Sideloadly 也支持已越狱设备。

### 若启动时报 dyld 符号错误

工程默认 `ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES`（把 Swift 运行库打进包里，兼容性最好）。
如果包体偏大想省空间，可在 `project.yml` 里改成 `"NO"` —— iOS 12.5.8 自带 Swift 运行库，通常也能跑。

---

## 使用说明

- **导入**：书库右上角「+」→ 从「文件」选择 txt/epub/pdf/docx/rtf/html（可多选）。
  或电脑用 iTunes（Windows）/ Finder（Mac）→ 设备 → 文件共享 → 轻阅读 → 把书拖进 `Books`。
- **阅读**：点一下屏幕中央 → 呼出/隐藏上下栏；底部滑杆拖动定位；「更多」里有设置、自动滚屏、添加书签、高亮列表、清空本书书签。
- **高亮**：长按选中文字后点底部「高亮」→ 选颜色（无选中时点「高亮」则打开高亮列表）。PDF 用「更多 → 高亮当前页」摘录当前页文字。
- **翻页**：设置 →「翻页方式」（上下滚动 / 左右平移 / 仿真翻页）；左右翻页时点屏幕左侧上一页、右侧下一页。
- **音量键**：设置 →「音量键翻页」打开后，音量键 = 翻页。
- **朗读**：底部「朗读」开始/停止，语速在「设置 → 朗读语速」。
- **设置**：底部「更多」→「阅读设置」，调完点左上角「完成」返回。
- **统计**：书库左上角「统计」。
- **排序/筛选**：左上角「排序」里可同时切换排序方式和「未读 / 在读 / 已读」筛选。
- **护眼与密码**：设置 →「提醒与保护」里有夜间自动主题、连续阅读提醒、提醒间隔、启动密码。

## 已知限制

- 仅 TXT / EPUB / PDF / HTML / DOCX / RTF；**不支持** MOBI/AZW3/DJVU/CBZ/CBR/CHM/FB2/UMD/ODT。
- EPUB 使用简化解析（OPF spine 顺序），复杂排版/DRM 书籍可能显示不佳。
- PDF 夜间模式只改背景，页面本身仍为白底；PDF 的高亮是「摘录当前页文字」，不是选区高亮。
- 无云同步、无词典、无双页模式、无倾斜翻页、无桌面小部件（原版能力对照见 `功能对照表.md`）。
- 未做 App Store 上架适配（无图标以外的营销素材、无隐私清单）；面向越狱/自签安装。

这些都可以按需继续扩展：新格式在 `BookType` 加枚举 + 一个 Reader 控制器即可接入。
