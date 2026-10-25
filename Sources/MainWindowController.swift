import Cocoa
import WebKit
import Network

extension NSToolbarItem.Identifier {
    static let back = Self("back"), forward = Self("forward"), reload = Self("reload"), home = Self("home")
    static let openInBrowser = Self("openInBrowser"), communitySearch = Self("communitySearch")
    static let downloads = Self("downloads"), share = Self("share"), more = Self("more"), sidebar = Self("nativeSidebar")
}

final class MainWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation, NSSearchFieldDelegate {
    let webView: WKWebView
    let splitController = NSSplitViewController()
    let sidebar = SidebarController()
    private(set) var sidebarItem: NSSplitViewItem!
    let findBar = FindBar(frame: .zero)
    private var findHeight: NSLayoutConstraint!
    private let progress = ProgressLine(frame: .zero)
    private let errorOverlay = ErrorOverlay(frame: .zero)
    private let notice = FloatingNotice(frame: .zero)
    private let scriptHandler = WeakScriptHandler()
    private var observations: [NSKeyValueObservation] = []
    private var tokens: [NSObjectProtocol] = []
    private let defaults = Prefs.defaults
    private var pendingRestore: ReadingPosition?
    private var hasLoadedContent = false
    private var draftPresent = false
    private var closingApproved = false
    private var closePromptOpen = false
    private var pendingNoticeAction: (() -> Void)?
    private var noticeGeneration = 0
    private var downloadPopover: NSPopover?
    var searchItem: NSSearchToolbarItem?
    private var searchPopover: NSPopover?
    private var findSequence = 0
    private var lastObservedURL: URL?
    private var crashCount = 0
    var onClose: ((MainWindowController) -> Void)?
    var newWindow: ((URL?, WKWebViewConfiguration?) -> MainWindowController?)?
    var hasUnsavedDraft: Bool { draftPresent }

    init(url: URL? = nil, configuration: WKWebViewConfiguration? = nil, primary: Bool = false, deferLoad: Bool = false) {
        let config = configuration ?? WKWebViewConfiguration()
        if configuration == nil {
            config.websiteDataStore = AppConfig.preview ? .nonPersistent() : .default()
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            if #available(macOS 12.3, *) { config.preferences.isElementFullscreenEnabled = true }
        }
        // A popup configuration can share a user content controller; give this window its own bridge.
        config.userContentController = WKUserContentController()
        config.userContentController.add(scriptHandler, contentWorld: .defaultClient, name: "nativeState")
        config.userContentController.addUserScript(WKUserScript(source: PageBridge.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true; webView.allowsMagnification = true
        webView.underPageBackgroundColor = .windowBackgroundColor
        webView.pageZoom = max(0.5, min(3, defaults.object(forKey: Prefs.pageZoom) as? Double ?? 1))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: AppConfig.windowSize), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = AppConfig.appName; window.minSize = NSSize(width: 860, height: 560)
        window.backgroundColor = .windowBackgroundColor; window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed // Multi-window works without depending on WebKit tab lifecycle.
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.autorecalculatesKeyViewLoop = true
        window.center()
        if primary { window.setFrameAutosaveName(AppConfig.preview ? "LinuxDoPreviewWindowV2" : "LinuxDoMainWindowV2") }
        // A previously saved narrow frame makes the unified toolbar and reading column feel cramped.
        if window.frame.width < 1180 || window.frame.height < 760 {
            window.setContentSize(AppConfig.windowSize)
            window.center()
        }
        super.init(window: window)
        scriptHandler.target = self; window.delegate = self
        webView.navigationDelegate = self; webView.uiDelegate = self
        setupContent(); setupToolbar(); observe()
        applyPreferences()
        if !deferLoad {
            let saved = defaults.string(forKey: Prefs.lastURL).flatMap(URL.init(string:))
            let initial = url ?? (saved.flatMap { (AppConfig.preview ? AppConfig.isPreview($0) : AppConfig.isInternal($0)) ? $0 : nil }) ?? AppConfig.route("/latest")
            if defaults.bool(forKey: Prefs.restoreReading) { pendingRestore = ReadingStore.shared.position(for: initial) }
            load(initial)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nativeState", contentWorld: .defaultClient)
    }

    private func setupContent() {
        let content = NSViewController(); content.view = NSView()
        let container = content.view
        findBar.isHidden = true
        findBar.field.target = self; findBar.field.action = #selector(findNext(_:)); findBar.field.delegate = self
        findBar.field.sendsSearchStringImmediately = false
        findBar.previous.target = self; findBar.previous.action = #selector(findPrevious(_:))
        findBar.next.target = self; findBar.next.action = #selector(findNext(_:))
        findBar.done.target = self; findBar.done.action = #selector(hideFind(_:))
        errorOverlay.isHidden = true; errorOverlay.retryButton.target = self; errorOverlay.retryButton.action = #selector(reloadPage(_:))
        notice.isHidden = true; notice.actionButton.target = self; notice.actionButton.action = #selector(noticeAction(_:))
        notice.dismissButton.target = self; notice.dismissButton.action = #selector(dismissNotice(_:))
        for v in [findBar, webView, errorOverlay, progress, notice] { container.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        findHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor), findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor), findHeight,
            webView.topAnchor.constraint(equalTo: findBar.bottomAnchor), webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor), webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            errorOverlay.topAnchor.constraint(equalTo: webView.topAnchor), errorOverlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            errorOverlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor), errorOverlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            progress.topAnchor.constraint(equalTo: webView.topAnchor), progress.leadingAnchor.constraint(equalTo: webView.leadingAnchor), progress.trailingAnchor.constraint(equalTo: webView.trailingAnchor), progress.heightAnchor.constraint(equalToConstant: 2),
            notice.topAnchor.constraint(equalTo: webView.topAnchor, constant: 12), notice.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            notice.leadingAnchor.constraint(greaterThanOrEqualTo: webView.leadingAnchor, constant: 16), notice.trailingAnchor.constraint(lessThanOrEqualTo: webView.trailingAnchor, constant: -16),
            notice.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
        ])
        sidebar.onNavigate = { [weak self] path in self?.navigate(AppConfig.route(path)) }
        sidebar.onSettings = { SettingsController.shared.show() }
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 220; sidebarItem.maximumThickness = 320
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none
        sidebarItem.canCollapse = true; sidebarItem.canCollapseFromWindowResize = true
        sidebarItem.isCollapsed = defaults.bool(forKey: "NativeSidebarCollapsedByUser")
        let detail = NSSplitViewItem(viewController: content); detail.minimumThickness = 560
        if #available(macOS 26.0, *) { detail.automaticallyAdjustsSafeAreaInsets = true }
        splitController.addSplitViewItem(sidebarItem); splitController.addSplitViewItem(detail)
        splitController.splitView.autosaveName = AppConfig.preview ? "LinuxDoPreviewSplitV2" : "LinuxDoNativeSplitV2"
        window?.contentViewController = splitController
        if defaults.object(forKey: "NSSplitView Subview Frames LinuxDoNativeSplitV2") == nil { splitController.splitView.setPosition(248, ofDividerAt: 0) }
        enforceComfortableFrame()
    }
    private func enforceComfortableFrame() {
        guard let window else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 28, dy: 20) ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = NSSize(width: min(1360, visible.width), height: min(880, visible.height))
        if window.frame.width < min(1180, target.width) || window.frame.height < min(760, target.height) {
            window.setFrame(NSRect(origin: .zero, size: target), display: false)
            window.center()
        }
    }
    private func observe() {
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in DispatchQueue.main.async {
            guard let self else { return }; let parsed = PageTitle.parse(wv.title)
            self.window?.title = parsed.text
            self.window?.subtitle = AppConfig.preview ? "离线界面预览" : "linux.do"
            if self.window?.isKeyWindow == true { NSApp.dockTile.badgeLabel = parsed.badge }
        } })
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in DispatchQueue.main.async { self?.progress.update(progress: wv.estimatedProgress, loading: wv.isLoading) } })
        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in DispatchQueue.main.async {
            self?.progress.update(progress: wv.estimatedProgress, loading: wv.isLoading); self?.window?.toolbar?.validateVisibleItems()
        } })
        for key in [\WKWebView.canGoBack, \WKWebView.canGoForward] {
            observations.append(webView.observe(key, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.window?.toolbar?.validateVisibleItems() } })
        }
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.urlChanged() } })
        observations.append(sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in DispatchQueue.main.async {
            self?.configurePage()
        } })
        tokens.append(NotificationCenter.default.addObserver(forName: .linuxDoPreferencesChanged, object: nil, queue: .main) { [weak self] note in
            if note.object as? String == "positionsCleared" { ReadingStore.shared.clear() }
            self?.applyPreferences()
        })
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.notice.rebuildMaterial() })
        tokens.append(NotificationCenter.default.addObserver(forName: .linuxDoDownloadsChanged, object: nil, queue: .main) { [weak self] _ in
            let n = DownloadManager.shared.activeCount
            self?.window?.toolbar?.items.first { $0.itemIdentifier == .downloads }?.toolTip = n > 0 ? "下载（\(n) 个进行中）" : "下载"
        })
    }
    private func urlChanged() {
        let url = webView.url; sidebar.synchronize(url: url)
        if url != lastObservedURL {
            lastObservedURL = url
            if let url, AppConfig.isInternal(url) || AppConfig.isPreview(url) { defaults.set(url.absoluteString, forKey: Prefs.lastURL) }
        }
        configurePage(); window?.toolbar?.validateVisibleItems()
    }
    func applyPreferences() {
        webView.customUserAgent = defaults.bool(forKey: Prefs.compatibilityUA) ? AppConfig.legacyUserAgent : nil
        if #available(macOS 14.0, *), !AppConfig.preview {
            let store = webView.configuration.websiteDataStore
            if defaults.bool(forKey: Prefs.proxyEnabled), let p = ProxyEndpoint.parse(defaults.string(forKey: Prefs.proxyURL) ?? AppConfig.defaultProxy), let port = NWEndpoint.Port(rawValue: p.port) {
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(p.host), port: port)
                store.proxyConfigurations = [p.socks ? ProxyConfiguration(socksv5Proxy: endpoint) : ProxyConfiguration(httpCONNECTProxy: endpoint)]
            } else { store.proxyConfigurations = [] }
        }
        notice.rebuildMaterial(); configurePage()
    }
    private func script(_ source: String, completion: ((Result<Any, Error>) -> Void)? = nil) {
        guard AppConfig.isInternal(webView.url) || AppConfig.isPreview(webView.url) else { return }
        webView.evaluateJavaScript(source, in: nil, in: .defaultClient, completionHandler: completion)
    }
    private func configurePage() { script(PageBridge.configureScript(sidebarVisible: sidebarItem?.isCollapsed == false)) }
    func capturePosition() { script("window.__linuxDoNative?.capture();") }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, AppConfig.isInternal(message.frameInfo.request.url) || AppConfig.isPreview(message.frameInfo.request.url),
              let data = message.body as? [String: Any], let type = data["type"] as? String else { return }
        switch type {
        case "ready": configurePage(); restoreIfNeeded()
        case "draft": draftPresent = data["value"] as? Bool ?? false
        case "position":
            guard defaults.bool(forKey: Prefs.restoreReading), let url = data["url"] as? String, let x = data["x"] as? Double, let y = data["y"] as? Double else { return }
            ReadingStore.shared.save(.init(url: url, x: x, y: y, postID: data["postID"] as? String, offset: data["offset"] as? Double, updated: Date().timeIntervalSince1970))
        default: break
        }
    }
    private func restoreIfNeeded() {
        guard let position = pendingRestore, position.url == webView.url?.absoluteString else { return }
        pendingRestore = nil
        if let data = try? JSONEncoder().encode(position), let json = String(data: data, encoding: .utf8) { script("window.__linuxDoNative?.restore(\(json));") }
    }
    func load(_ url: URL) {
        if AppConfig.isPreview(url) { webView.loadFileURL(url, allowingReadAccessTo: AppConfig.previewURL.deletingLastPathComponent()) }
        else { webView.load(URLRequest(url: url)) }
    }
    func navigate(_ url: URL) { withDraftProtection { [weak self] in self?.capturePosition(); self?.load(url) } }
    private func withDraftProtection(_ action: @escaping () -> Void) {
        guard draftPresent else { action(); return }
        // The site can clear its editor without an input event after posting, so confirm live state first.
        refreshDraftState { [weak self] hasDraft in
            guard let self, hasDraft, let window = self.window else { action(); return }
            let alert = NSAlert(); alert.messageText = "当前有未发送的回复"; alert.informativeText = "继续会离开当前编辑页面。你可以先留在这里保存草稿。"
            alert.addButton(withTitle: "留在页面"); alert.addButton(withTitle: "继续离开")
            alert.beginSheetModal(for: window) { if $0 == .alertSecondButtonReturn { action() } }
        }
    }
    func refreshDraftState(_ completion: @escaping (Bool) -> Void) {
        guard AppConfig.isInternal(webView.url) || AppConfig.isPreview(webView.url) else { draftPresent = false; completion(false); return }
        webView.evaluateJavaScript("window.__linuxDoNative ? window.__linuxDoNative.hasDraft() : false", in: nil, in: .defaultClient) { [weak self] result in
            let value = (try? result.get()) as? Bool ?? false
            self?.draftPresent = value; completion(value)
        }
    }
    @objc func navBack(_ sender: Any?) { withDraftProtection { [weak self] in self?.capturePosition(); self?.webView.goBack() } }
    @objc func navForward(_ sender: Any?) { withDraftProtection { [weak self] in self?.capturePosition(); self?.webView.goForward() } }
    @objc func goHome(_ sender: Any?) { navigate(AppConfig.route("/latest")) }
    @objc func reloadPage(_ sender: Any?) { withDraftProtection { [weak self] in guard let self else { return }; self.errorOverlay.isHidden = true; self.dismissNotice(nil); if self.webView.url == nil { self.load(AppConfig.route("/latest")) } else { self.webView.reload() } } }
    @objc func reloadFromOrigin(_ sender: Any?) { withDraftProtection { [weak self] in self?.webView.reloadFromOrigin() } }
    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom + 0.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom - 0.1) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }
    private func setZoom(_ value: CGFloat) { webView.pageZoom = (min(3, max(0.5, value)) * 10).rounded() / 10; defaults.set(Double(webView.pageZoom), forKey: Prefs.pageZoom) }
    @objc func copyPageURL(_ sender: Any?) {
        guard let url = webView.url else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showNotice("页面链接已复制", actionTitle: nil, action: nil, temporary: true)
    }
    @objc func openInBrowser(_ sender: Any?) { NSWorkspace.shared.open(webView.url ?? AppConfig.homeURL) }
    @objc func toggleNativeSidebar(_ sender: Any?) {
        let collapsed = !sidebarItem.isCollapsed
        defaults.set(collapsed, forKey: "NativeSidebarCollapsedByUser")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            sidebarItem.animator().isCollapsed = collapsed
        }
    }
    @objc func showSettings(_ sender: Any?) { SettingsController.shared.show() }
    @objc func showFind(_ sender: Any?) { findBar.isHidden = false; findHeight.constant = 44; window?.makeFirstResponder(findBar.field) }
    @objc func hideFind(_ sender: Any?) { findBar.isHidden = true; findHeight.constant = 0; findSequence += 1; window?.makeFirstResponder(webView) }
    @objc func findNext(_ sender: Any?) { performFind(backward: false) }
    @objc func findPrevious(_ sender: Any?) { performFind(backward: true) }
    private func performFind(backward: Bool) {
        if findBar.isHidden { showFind(nil) }
        let query = findBar.field.stringValue
        guard !query.isEmpty else { findBar.status.stringValue = ""; return }
        findSequence += 1; let sequence = findSequence
        let config = WKFindConfiguration(); config.backwards = backward; config.wraps = true; config.caseSensitive = false
        webView.find(query, configuration: config) { [weak self] result in
            guard let self, sequence == self.findSequence else { return }
            self.findBar.status.stringValue = result.matchFound ? "找到匹配" : "没有匹配"
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), control === findBar.field { hideFind(nil); return true }; return false
    }
    @objc func focusSearch(_ sender: Any?) {
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == .communitySearch }) as? NSSearchToolbarItem { item.beginSearchInteraction(); return }
        let field = NSSearchField(frame: NSRect(x: 16, y: 16, width: 310, height: 26)); field.placeholderString = "搜索社区"; field.target = self; field.action = #selector(submitSearch(_:)); field.sendsWholeSearchString = true
        let vc = NSViewController(); vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 342, height: 58)); vc.view.addSubview(field)
        let popover = NSPopover(); popover.contentViewController = vc; popover.behavior = .transient
        popover.show(relativeTo: NSRect(x: webView.bounds.midX, y: webView.bounds.maxY - 2, width: 1, height: 1), of: webView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(field); searchPopover = popover
    }
    @objc func submitSearch(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }; searchPopover?.close(); searchItem?.endSearchInteraction(); navigate(AppConfig.searchURL(query))
    }
    @objc func showDownloads(_ sender: Any?) {
        if downloadPopover?.isShown == true { downloadPopover?.close(); return }
        let popover = NSPopover(); popover.contentViewController = DownloadsController(); popover.behavior = .transient
        let anchor = (sender as? NSView) ?? window?.toolbar?.items.first(where: { $0.itemIdentifier == .downloads })?.view
        if let anchor { popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY) }
        else { popover.show(relativeTo: NSRect(x: webView.bounds.maxX - 24, y: webView.bounds.maxY - 2, width: 1, height: 1), of: webView, preferredEdge: .minY) }
        downloadPopover = popover
    }
    @objc func sharePage(_ sender: Any?) {
        guard let url = webView.url else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = (sender as? NSView) ?? webView
        picker.show(relativeTo: anchor === webView ? NSRect(x: anchor.bounds.maxX - 80, y: anchor.bounds.maxY - 2, width: 1, height: 1) : anchor.bounds, of: anchor, preferredEdge: .minY)
    }
    func showNotice(_ text: String, actionTitle: String?, action: (() -> Void)?, temporary: Bool = false) {
        noticeGeneration += 1; let sequence = noticeGeneration
        notice.label.stringValue = text; notice.label.toolTip = text
        notice.actionButton.isHidden = actionTitle == nil; notice.actionButton.title = actionTitle ?? ""
        pendingNoticeAction = action; notice.isHidden = false
        if temporary { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.noticeGeneration == sequence { self?.dismissNotice(nil) } } }
    }
    @objc private func dismissNotice(_ sender: Any?) { noticeGeneration += 1; notice.isHidden = true; pendingNoticeAction = nil }
    @objc private func noticeAction(_ sender: Any?) { let action = pendingNoticeAction; dismissNotice(nil); action?() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        capturePosition()
        if closingApproved || !draftPresent { return true }
        if !closePromptOpen {
            closePromptOpen = true
            refreshDraftState { [weak self] hasDraft in
                guard let self else { return }
                guard hasDraft else { self.closePromptOpen = false; self.closingApproved = true; sender.performClose(nil); return }
                let alert = NSAlert(); alert.messageText = "关闭前保存回复？"; alert.informativeText = "当前有未发送的回复。关闭后本应用不会保留编辑内容。"
                alert.addButton(withTitle: "继续编辑"); alert.addButton(withTitle: "关闭窗口")
                alert.beginSheetModal(for: sender) { [weak self] result in
                    guard let self else { return }; self.closePromptOpen = false
                    if result == .alertSecondButtonReturn { self.closingApproved = true; sender.performClose(nil) }
                }
            }
        }
        return false
    }
    func windowWillClose(_ notification: Notification) { downloadPopover?.close(); onClose?(self) }
    func windowDidBecomeKey(_ notification: Notification) { NSApp.dockTile.badgeLabel = PageTitle.parse(webView.title).badge }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { decisionHandler(.allow); return }
        if AppConfig.preview && !["file", "blob", "data", "about"].contains(scheme) { decisionHandler(.cancel); return }
        if action.shouldPerformDownload { decisionHandler(.download); return }
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command) {
            if AppConfig.isInternal(url) || AppConfig.isPreview(url) { _ = newWindow?(url, nil) } else { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel); return
        }
        if !["http", "https", "about", "blob", "data", "file"].contains(scheme) { NSWorkspace.shared.open(url); decisionHandler(.cancel); return }
        // Keep redirects and authentication flows in the web view. Ordinary external links open in the browser.
        if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame == true, ["http", "https"].contains(scheme), !AppConfig.isInternal(url) {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        decisionHandler(!response.canShowMIMEType || disposition.hasPrefix("attachment") ? .download : .allow)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { DownloadManager.shared.register(download, window: window) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { DownloadManager.shared.register(download, window: window) }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { dismissNotice(nil) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedContent = true; errorOverlay.isHidden = true; draftPresent = false
        urlChanged(); configurePage(); restoreIfNeeded()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }
    private func showError(_ error: Error) {
        let e = error as NSError
        if (e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled) || (e.domain == "WebKitErrorDomain" && e.code == 102) { return }
        progress.update(progress: 1, loading: false)
        if hasLoadedContent { showNotice("连接暂时中断，已保留当前页面", actionTitle: "重试", action: { [weak self] in self?.reloadPage(nil) }) }
        else { errorOverlay.messageLabel.stringValue = e.localizedDescription; errorOverlay.isHidden = false }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        crashCount += 1
        // Never silently reload an editor after a process failure.
        if draftPresent || crashCount > 1 { showNotice("网页进程已停止。重新加载后请检查站点保存的草稿。", actionTitle: "重新加载", action: { [weak self] in self?.draftPresent = false; self?.reloadPage(nil) }) }
        else { pendingRestore = webView.url.flatMap { ReadingStore.shared.position(for: $0) }; webView.reload() }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Return a real WebView for window.open so authentication callbacks keep their opener.
        return newWindow?(nil, configuration)?.webView
    }
    func webViewDidClose(_ webView: WKWebView) { window?.performClose(nil) }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        guard let window else { completionHandler(nil); return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories; panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window else { completionHandler(); return }; let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window else { completionHandler(false); return }; let alert = NSAlert(); alert.messageText = message
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消"); alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let window else { completionHandler(nil); return }; let alert = NSAlert(); alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24)); field.stringValue = defaultText ?? ""; alert.accessoryView = field
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消"); alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptBeforeUnloadConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window else { completionHandler(false); return }
        let alert = NSAlert(); alert.messageText = "离开当前页面？"; alert.informativeText = message
        alert.addButton(withTitle: "留在页面"); alert.addButton(withTitle: "离开")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertSecondButtonReturn) }
    }
}
