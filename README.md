# LinuxDo for macOS

LinuxDo 2.0 是基于 AppKit 和 WKWebView 的 macOS 社区客户端。应用使用原生窗口、工具栏和菜单，帖子、登录及回复功能由 linux.do 网页承载。

这是独立客户端项目，与 linux.do 官方的关联关系未经确认。

## 功能

- 原生统一工具栏：后退、前进、社区搜索、刷新、下载、分享。
- 可收起的快捷侧栏；展开时可隐藏网页中重复的侧栏。
- macOS 26 及更新系统使用 Liquid Glass 临时提示，较早系统使用视觉效果材质。
- 页内查找、多个窗口、正文阅读字号和行距设置。
- 阅读位置记录、回复草稿提醒、下载进度及目标位置选择。
- 浅色、深色及系统外观；响应减少动态效果和减少透明度设置。
- 可选 HTTP CONNECT / SOCKS5 代理，代理配置需要 macOS 14 或更新系统。
- 保留既有应用标识 `com.pake.acea3c3`，沿用同一标识下的 WebKit 网站数据。

原生快捷侧栏默认收起，可通过工具栏按钮或 `⌥⌘S` 打开。

## 构建

需要 macOS、包含 macOS 26 或更新 SDK 的 Xcode / Command Line Tools，以及 `swiftc`、`sips`、`iconutil`、`lipo`、`codesign` 和 `hdiutil`。项目直接使用系统框架，没有第三方 Swift 包依赖。

```sh
./build.sh release
```

产物：

```text
build/LinuxDo.app
build/LinuxDo.dmg
```

发布构建包含 Apple 芯片与 Intel 两种架构，部署目标为 macOS 12。当前已在 macOS 27 的 Apple 芯片设备上运行；较早 macOS 与 Intel 真机的运行情况仍需验证。

构建脚本使用本地 ad-hoc 签名，未配置 Developer ID 签名与 Apple 公证。

## 开发与验证

```sh
# 核心逻辑测试：域名、搜索编码、代理、下载文件名及阅读位置
./build.sh test

# 当前 Mac 架构的调试版
./build.sh debug

# 离线界面预览
open build/LinuxDo.app --args --preview
```

预览使用独立设置域和非持久化网站数据存储。调试构建还包含 `--preview --self-test` 集成测试入口；该测试目前假定原生侧栏展开、阅读字号为 16 px，运行前需在预览中设置对应状态。真实账号浏览测试需单独执行。

`build.sh` 会重建 `build/LinuxDo.app` 和相关构建产物。`build/` 中的旧版回退应用与账号数据不提交到仓库。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建窗口 | `⌘N` |
| 搜索社区 | `⌘K` |
| 页内查找 | `⌘F` |
| 下一个 / 上一个匹配 | `⌘G` / `⇧⌘G` |
| 重新加载 | `⌘R` |
| 后退 / 前进 | `⌘[` / `⌘]` |
| 显示或收起侧栏 | `⌥⌘S` |
| 下载 | `⌥⌘L` |
| 设置 | `⌘,` |

## 代码结构

```text
Sources/       AppKit 窗口、工具栏、设置、下载及 WebKit 桥接
Resources/     应用信息、图标与离线预览页面
Tools/         图标生成工具
Tests/         核心逻辑测试
build.sh       调试、测试及通用发布构建
```

WebKit 桥接传递阅读位置和是否存在草稿的布尔值，不传递 Cookie 或草稿正文。真实账号会话由 WebKit 网站数据存储管理，不属于仓库内容。
