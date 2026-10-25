import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var windows: [MainWindowController] = []
    private var terminationConfirmed = false
    private var testHarness: AnyObject?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.applyAppearance()
        NSApp.mainMenu = buildMainMenu()
        _ = makeWindow(primary: true)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        if CommandLine.arguments.contains("--self-test"), AppConfig.preview {
            let harness = IntegrationTests(app: self); testHarness = harness; harness.start()
        }
        #endif
    }
    @discardableResult func makeWindow(url: URL? = nil, configuration: WKWebViewConfiguration? = nil, primary: Bool = false) -> MainWindowController {
        let controller = MainWindowController(url: url, configuration: configuration, primary: primary, deferLoad: configuration != nil)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        controller.newWindow = { [weak self] url, config in self?.makeWindow(url: url, configuration: config) }
        windows.append(controller)
        if !primary { controller.window?.cascadeTopLeft(from: NSPoint(x: 120 + windows.count * 24, y: 860 - windows.count * 24)) }
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { if let first = windows.first { first.showWindow(nil); first.window?.makeKeyAndOrderFront(nil) } else { makeWindow(primary: true) } }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windows.forEach { $0.capturePosition() }
        if terminationConfirmed { return .terminateNow }
        let draftWindow = windows.first { $0.hasUnsavedDraft }?.window
        let downloading = DownloadManager.shared.activeCount > 0
        guard draftWindow != nil || downloading else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = draftWindow != nil ? "还有未发送的回复" : "下载仍在进行"
        alert.informativeText = "退出将关闭页面并中断进行中的下载。你可以继续使用，处理完成后再退出。"
        alert.addButton(withTitle: "继续使用"); alert.addButton(withTitle: "退出 LinuxDo")
        if let window = draftWindow ?? windows.first?.window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { [weak self] response in
                self?.terminationConfirmed = response == .alertSecondButtonReturn
                sender.reply(toApplicationShouldTerminate: response == .alertSecondButtonReturn)
            }
            return .terminateLater
        }
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    @objc func newWindow(_ sender: Any?) { makeWindow(url: AppConfig.route("/latest")) }
    @objc func showSettings(_ sender: Any?) { SettingsController.shared.show() }
    @objc func showMainWindow(_ sender: Any?) { if let c = windows.first { c.showWindow(nil); c.window?.makeKeyAndOrderFront(nil) } else { makeWindow(primary: true) } }
    @objc func openWebsite(_ sender: Any?) { NSWorkspace.shared.open(AppConfig.homeURL) }
    @objc func showAbout(_ sender: Any?) { NSApp.orderFrontStandardAboutPanel(options: [.credits: NSAttributedString(string: "为 macOS 打造的 LinuxDo 社区客户端\n原生导航 · 舒适阅读 · Liquid Glass", attributes: [.font: NSFont.systemFont(ofSize: 11)])]) }
    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = mods; item.target = target; return item
    }
    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title); items.forEach(menu.addItem)
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: ""); parent.submenu = menu; return parent
    }
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu(), services = NSMenu(title: "服务")
        NSApp.servicesMenu = services; let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: ""); servicesItem.submenu = services
        main.addItem(submenu("LinuxDo", [item("关于 LinuxDo", #selector(showAbout(_:)), target: self), .separator(), item("设置…", #selector(showSettings(_:)), ",", target: self), .separator(), servicesItem, .separator(), item("隐藏 LinuxDo", #selector(NSApplication.hide(_:)), "h"), item("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]), item("全部显示", #selector(NSApplication.unhideAllApplications(_:))), .separator(), item("退出 LinuxDo", #selector(NSApplication.terminate(_:)), "q")]))
        main.addItem(submenu("文件", [item("新建窗口", #selector(newWindow(_:)), "n", target: self), item("关闭窗口", #selector(NSWindow.performClose(_:)), "w"), .separator(), item("分享页面…", #selector(MainWindowController.sharePage(_:)))]))
        main.addItem(submenu("编辑", [item("撤销", Selector(("undo:")), "z"), item("重做", Selector(("redo:")), "z", [.command, .shift]), .separator(), item("剪切", #selector(NSText.cut(_:)), "x"), item("拷贝", #selector(NSText.copy(_:)), "c"), item("粘贴", #selector(NSText.paste(_:)), "v"), item("粘贴并匹配样式", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]), item("全选", #selector(NSText.selectAll(_:)), "a"), .separator(), item("页内查找…", #selector(MainWindowController.showFind(_:)), "f"), item("下一个匹配", #selector(MainWindowController.findNext(_:)), "g"), item("上一个匹配", #selector(MainWindowController.findPrevious(_:)), "g", [.command, .shift]), item("搜索社区…", #selector(MainWindowController.focusSearch(_:)), "k")]))
        main.addItem(submenu("显示", [item("显示或收起侧栏", #selector(MainWindowController.toggleNativeSidebar(_:)), "s", [.command, .option]), .separator(), item("重新加载", #selector(MainWindowController.reloadPage(_:)), "r"), item("强制重新加载", #selector(MainWindowController.reloadFromOrigin(_:)), "r", [.command, .shift]), .separator(), item("实际大小", #selector(MainWindowController.actualSize(_:)), "0"), item("放大", #selector(MainWindowController.zoomIn(_:)), "="), item("缩小", #selector(MainWindowController.zoomOut(_:)), "-"), .separator(), item("下载", #selector(MainWindowController.showDownloads(_:)), "l", [.command, .option]), item("自定义工具栏…", #selector(NSWindow.runToolbarCustomizationPalette(_:))), .separator(), item("进入全屏幕", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])]))
        main.addItem(submenu("前往", [item("后退", #selector(MainWindowController.navBack(_:)), "["), item("前进", #selector(MainWindowController.navForward(_:)), "]"), item("首页", #selector(MainWindowController.goHome(_:)), "h", [.command, .shift]), .separator(), item("拷贝页面链接", #selector(MainWindowController.copyPageURL(_:)), "c", [.command, .shift]), item("在浏览器中打开", #selector(MainWindowController.openInBrowser(_:)), "o", [.command, .shift])]))
        let windows = submenu("窗口", [item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"), item("缩放", #selector(NSWindow.performZoom(_:))), item("LinuxDo 主窗口", #selector(showMainWindow(_:)), "1", target: self), .separator(), item("前置全部窗口", #selector(NSApplication.arrangeInFront(_:)))])
        NSApp.windowsMenu = windows.submenu; main.addItem(windows)
        let help = submenu("帮助", [item("在浏览器中访问 linux.do", #selector(openWebsite(_:)), target: self)])
        NSApp.helpMenu = help.submenu; main.addItem(help)
        return main
    }
}
