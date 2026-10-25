import Cocoa

final class SettingsController: NSWindowController {
    static let shared = SettingsController()
    private let appearance = NSSegmentedControl(labels: ["跟随系统", "浅色", "深色"], trackingMode: .selectOne, target: nil, action: nil)
    private let font = NSSlider(value: 16, minValue: 13, maxValue: 22, target: nil, action: nil)
    private let fontValue = textLabel("16 px", size: 12, secondary: true)
    private let line = NSSegmentedControl(labels: ["紧凑", "舒适", "宽松"], trackingMode: .selectOne, target: nil, action: nil)
    private let proxy = NSTextField()
    private let proxyStatus = textLabel("", size: 11, secondary: true)
    private var checks: [String: NSButton] = [:]
    private var proxyToggle: NSButton!

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "LinuxDo 设置"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center(); window.setFrameAutosaveName(AppConfig.preview ? "PreviewSettings" : "LinuxDoSettings")
        let tabs = NSTabView(); tabs.tabViewType = .topTabsBezelBorder
        tabs.addTabViewItem(makeAppearanceTab()); tabs.addTabViewItem(makeBrowsingTab()); tabs.addTabViewItem(makeNetworkTab())
        let content = NSView(); content.addSubview(tabs); pin(tabs, to: content, inset: 20)
        window.contentView = content
        synchronize()
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { synchronize(); showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    private func section(_ title: String, _ description: String? = nil) -> NSView {
        let stack = NSStackView(views: [textLabel(title, size: 14, weight: .semibold)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        if let description { let note = NSTextField(wrappingLabelWithString: description); note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 12); note.preferredMaxLayoutWidth = 450; stack.addArrangedSubview(note) }
        return stack
    }
    private func checkbox(_ title: String, key: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        b.identifier = NSUserInterfaceItemIdentifier(key); checks[key] = b
        return b
    }
    private func tab(_ title: String, views: [NSView]) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title); item.label = title
        let wrapper = NSView()
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        wrapper.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 30), stack.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor, constant: -20)])
        item.view = wrapper; return item
    }
    private func makeAppearanceTab() -> NSTabViewItem {
        appearance.target = self; appearance.action = #selector(appearanceChanged)
        font.target = self; font.action = #selector(fontChanged); font.numberOfTickMarks = 10; font.allowsTickMarkValuesOnly = true
        font.setAccessibilityLabel("正文字号"); font.widthAnchor.constraint(equalToConstant: 250).isActive = true
        line.target = self; line.action = #selector(lineChanged)
        return tab("外观与阅读", views: [
            section("让内容成为主角", "原生导航跟随 macOS 外观；网页保留站点主题与编辑器。"), appearance,
            checkbox("使用 Liquid Glass 浮层", key: Prefs.glass),
            section("阅读排版", "只调整帖子正文；代码、登录与回复功能保持原样。"),
            checkbox("启用舒适阅读排版", key: Prefs.reading),
            NSStackView(views: [textLabel("字号"), font, fontValue]),
            NSStackView(views: [textLabel("行距"), line]),
            checkbox("显示原生侧栏时，收起网页侧栏", key: Prefs.hideWebSidebar),
            section("尊重系统设置", "减少透明度、增强对比度和减少动态效果由系统控制。玻璃开关只控制自定义浮层，系统工具栏遵循 macOS 设置。")
        ])
    }
    private func makeBrowsingTab() -> NSTabViewItem {
        let clearPositions = NSButton(title: "清除本地阅读位置…", target: self, action: #selector(clearPositions))
        clearPositions.bezelStyle = .rounded
        return tab("浏览与下载", views: [
            section("继续上次的阅读", "重启时恢复最后页面和阅读位置。此功能不读取或保存回复内容。"),
            checkbox("恢复阅读位置", key: Prefs.restoreReading), clearPositions,
            section("下载", "下载完成后安静地留在下载面板中，不打断当前操作。"),
            checkbox("每次下载前询问保存位置", key: Prefs.downloadAsk),
            section("键盘操作", "⌘K  社区搜索\n⌘F  页内查找    ⌘G  下一个匹配\n⌘N  新窗口    ⌘W  关闭窗口\n⌘点击站内链接  新窗口打开\n⌥⌘S  显示或收起侧栏\n⌘,  打开设置")
        ])
    }
    private func makeNetworkTab() -> NSTabViewItem {
        proxy.placeholderString = AppConfig.defaultProxy
        proxy.setAccessibilityLabel("代理地址")
        proxy.widthAnchor.constraint(equalToConstant: 425).isActive = true
        proxyToggle = NSButton(checkboxWithTitle: "为 LinuxDo 单独使用代理", target: nil, action: nil)
        let save = NSButton(title: "保存网络设置", target: self, action: #selector(saveNetwork)); save.bezelStyle = .rounded
        return tab("网络", views: [section("连接方式", "默认跟随系统网络设置。独立代理支持 HTTP CONNECT 和 SOCKS5（macOS 14 及以后）。"), proxyToggle, proxy, proxyStatus, save,
            section("网页兼容性", "默认使用 WebKit 标识。修改后在下一次加载时生效；有未发送回复时请先保存。"),
            checkbox("使用旧版 Safari 兼容标识", key: Prefs.compatibilityUA)])
    }
    private func synchronize() {
        let d = Prefs.defaults
        appearance.selectedSegment = ["system", "light", "dark"].firstIndex(of: d.string(forKey: Prefs.appearance) ?? "system") ?? 0
        font.doubleValue = Prefs.boundedFont(d.double(forKey: Prefs.fontSize)); fontValue.stringValue = "\(Int(font.doubleValue)) px"
        let lh = d.double(forKey: Prefs.lineHeight); line.selectedSegment = lh < 1.65 ? 0 : (lh > 1.85 ? 2 : 1)
        for (key, button) in checks { button.state = d.bool(forKey: key) ? .on : .off }
        proxy.stringValue = d.string(forKey: Prefs.proxyURL) ?? AppConfig.defaultProxy
        proxyToggle.state = d.bool(forKey: Prefs.proxyEnabled) ? .on : .off
        if #unavailable(macOS 14.0) { proxyToggle.isEnabled = false; proxy.isEnabled = false }
    }
    private func broadcast() { NotificationCenter.default.post(name: .linuxDoPreferencesChanged, object: nil) }
    @objc private func checkChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        Prefs.defaults.set(sender.state == .on, forKey: key); broadcast()
    }
    @objc private func appearanceChanged() {
        Prefs.defaults.set(["system", "light", "dark"][appearance.selectedSegment], forKey: Prefs.appearance)
        Prefs.applyAppearance(); broadcast()
    }
    @objc private func fontChanged() { Prefs.defaults.set(font.doubleValue, forKey: Prefs.fontSize); fontValue.stringValue = "\(Int(font.doubleValue)) px"; broadcast() }
    @objc private func lineChanged() { Prefs.defaults.set([1.55, 1.75, 1.95][line.selectedSegment], forKey: Prefs.lineHeight); broadcast() }
    @objc private func saveNetwork() {
        let value = proxy.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if proxyToggle.state == .on && ProxyEndpoint.parse(value) == nil {
            proxyStatus.stringValue = "请输入 http://主机:端口 或 socks5://主机:端口（1–65535）"
            proxyStatus.textColor = .systemRed; return
        }
        Prefs.defaults.set(value, forKey: Prefs.proxyURL); Prefs.defaults.set(proxyToggle.state == .on, forKey: Prefs.proxyEnabled)
        proxyStatus.textColor = .secondaryLabelColor; proxyStatus.stringValue = "已保存；在下次页面加载时使用，不会自动刷新当前回复。"
        broadcast()
    }
    @objc private func clearPositions() {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "清除本地阅读位置？"; alert.informativeText = "账号、Cookie、收藏和网站数据都会保留。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "清除阅读位置")
        alert.beginSheetModal(for: window) { result in
            if result == .alertSecondButtonReturn { Prefs.defaults.removeObject(forKey: Prefs.positions); NotificationCenter.default.post(name: .linuxDoPreferencesChanged, object: "positionsCleared") }
        }
    }
}
