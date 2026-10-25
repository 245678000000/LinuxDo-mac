import Cocoa
import WebKit

extension MainWindowController {
    func setupToolbar() {
        let toolbar = NSToolbar(identifier: AppConfig.preview ? "LinuxDoPreviewToolbar" : "LinuxDoNativeToolbarV2")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = true; toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar; window?.toolbarStyle = .unified
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebar, .back, .forward, .flexibleSpace, .communitySearch, .reload, .downloads, .share, .more]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebar, .back, .forward, .flexibleSpace, .space, .communitySearch, .reload, .home, .downloads, .share, .openInBrowser, .more]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if id == .communitySearch {
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField.placeholderString = "搜索社区"
            item.searchField.setAccessibilityLabel("搜索社区")
            item.searchField.target = self; item.searchField.action = #selector(submitSearch(_:))
            item.searchField.sendsWholeSearchString = true; item.searchField.sendsSearchStringImmediately = false
            item.preferredWidthForSearchField = 220; item.label = "搜索社区"; item.toolTip = "搜索社区（⌘K）"
            searchItem = item; return item
        }
        if id == .more {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "更多"; item.toolTip = "更多操作"; item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "更多操作")
            let menu = NSMenu()
            for (title, selector) in [("拷贝页面链接", #selector(copyPageURL(_:))), ("在浏览器中打开", #selector(openInBrowser(_:))), ("页内查找…", #selector(showFind(_:))), ("设置…", #selector(showSettings(_:)))] {
                let entry = NSMenuItem(title: title, action: selector, keyEquivalent: ""); entry.target = self; menu.addItem(entry)
            }
            item.menu = menu; return item
        }
        let spec: (String, String, Selector, Bool)
        switch id {
        case .sidebar: spec = ("sidebar.left", "显示或收起侧栏（⌥⌘S）", #selector(toggleNativeSidebar(_:)), true)
        case .back: spec = ("chevron.backward", "后退（⌘[）", #selector(navBack(_:)), true)
        case .forward: spec = ("chevron.forward", "前进（⌘]）", #selector(navForward(_:)), true)
        case .reload: spec = ("arrow.clockwise", "重新加载（⌘R）", #selector(reloadPage(_:)), false)
        case .home: spec = ("house", "首页", #selector(goHome(_:)), false)
        case .downloads: spec = ("arrow.down.circle", "下载", #selector(showDownloads(_:)), false)
        case .share: spec = ("square.and.arrow.up", "分享页面", #selector(sharePage(_:)), false)
        case .openInBrowser: spec = ("safari", "在浏览器中打开", #selector(openInBrowser(_:)), false)
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = spec.1; item.toolTip = spec.1; item.image = NSImage(systemSymbolName: spec.0, accessibilityDescription: spec.1)
        item.target = self; item.action = spec.2; item.isBordered = true; item.isNavigational = spec.3
        return item
    }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier { case .back: return webView.canGoBack; case .forward: return webView.canGoForward; default: return true }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(navBack(_:)): return webView.canGoBack
        case #selector(navForward(_:)): return webView.canGoForward
        case #selector(actualSize(_:)): return webView.pageZoom != 1
        default: return true
        }
    }
}
