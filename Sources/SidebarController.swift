import Cocoa

struct SidebarRoute {
    let title: String
    let symbol: String
    let path: String?
    static let items: [SidebarRoute] = [
        .init(title: "社区", symbol: "", path: nil),
        .init(title: "最新", symbol: "clock", path: "/latest"),
        .init(title: "热门", symbol: "flame", path: "/top"),
        .init(title: "分类", symbol: "square.grid.2x2", path: "/categories"),
        .init(title: "我的空间", symbol: "", path: nil),
        .init(title: "未读", symbol: "circle.dotted", path: "/unread"),
        .init(title: "新话题", symbol: "sparkle", path: "/new"),
        .init(title: "收藏", symbol: "bookmark", path: "/my/bookmarks"),
        .init(title: "通知", symbol: "bell", path: "/my/notifications"),
        .init(title: "我的动态", symbol: "person.crop.circle", path: "/my/activity")
    ]
}

final class SidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var onNavigate: ((String) -> Void)?
    var onSettings: (() -> Void)?
    private var syncing = false
    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .sidebar; background.blendingMode = .behindWindow
        view = background
        let brand = textLabel("LINUX DO", size: 17, weight: .bold)
        let subtitle = textLabel(AppConfig.preview ? "离线界面预览" : "连接 · 分享 · 探索", size: 11, secondary: true)
        let brandStack = NSStackView(views: [brand, subtitle]); brandStack.orientation = .vertical
        brandStack.alignment = .leading; brandStack.spacing = 5
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        table.headerView = nil; table.style = .sourceList; table.allowsEmptySelection = true
        table.intercellSpacing = NSSize(width: 0, height: 5)
        table.addTableColumn(NSTableColumn(identifier: .init("navigation")))
        table.dataSource = self; table.delegate = self
        table.setAccessibilityLabel("社区导航")
        scroll.documentView = table
        let settings = NSButton(title: "设置", image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")!, target: self, action: #selector(openSettings))
        settings.bezelStyle = .inline; settings.imagePosition = .imageLeading
        let footer = NSStackView(views: [settings])
        for subview in [brandStack, scroll, footer] { view.addSubview(subview); subview.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            brandStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            brandStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            brandStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 22),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        ])
    }
    @objc private func openSettings() { onSettings?() }
    func numberOfRows(in tableView: NSTableView) -> Int { SidebarRoute.items.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { SidebarRoute.items[row].path == nil }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { SidebarRoute.items[row].path == nil ? 29 : 34 }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { SidebarRoute.items[row].path != nil }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let route = SidebarRoute.items[row]
        if route.path == nil {
            let cell = NSTableCellView(); let label = textLabel(route.title, size: 11, weight: .semibold, secondary: true)
            cell.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false; cell.textField = label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)])
            return cell
        }
        let cell = NSTableCellView()
        let label = textLabel(route.title, size: 13)
        let icon = NSImageView(image: NSImage(systemSymbolName: route.symbol, accessibilityDescription: nil)!)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular); icon.contentTintColor = .secondaryLabelColor
        cell.imageView = icon; cell.textField = label
        for v in [icon, label] { cell.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.widthAnchor.constraint(equalToConstant: 20), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)])
        cell.setAccessibilityLabel(route.title)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, table.selectedRow >= 0, let path = SidebarRoute.items[table.selectedRow].path else { return }
        onNavigate?(path)
    }
    func synchronize(url: URL?) {
        _ = view
        guard let url else { return }
        var path = url.path
        if AppConfig.isPreview(url) { path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "route" }?.value ?? "/latest" }
        syncing = true; defer { syncing = false }
        if let index = SidebarRoute.items.firstIndex(where: { $0.path == path || ($0.path == "/latest" && path == "/") }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
    }
}
