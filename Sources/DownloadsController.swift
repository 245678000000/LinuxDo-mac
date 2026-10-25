import Cocoa
import WebKit

final class DownloadRecord {
    let id = UUID()
    let download: WKDownload
    var name = "准备下载…"
    var destination: URL?
    var state = "正在下载"
    var finished = false
    var succeeded = false
    var observation: NSKeyValueObservation?
    init(_ download: WKDownload) { self.download = download }
    var fraction: Double { download.progress.fractionCompleted }
    var status: String {
        guard !finished else { return state }
        let completed = download.progress.completedUnitCount, total = download.progress.totalUnitCount
        if total > 0 { return "\(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" }
        return completed > 0 ? "已下载 \(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file))" : state
    }
}

final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private(set) var records: [DownloadRecord] = []
    private var owners: [ObjectIdentifier: NSWindow] = [:]
    private var changePending = false
    var activeCount: Int { records.filter { !$0.finished }.count }
    func register(_ download: WKDownload, window: NSWindow?) {
        let record = DownloadRecord(download)
        records.insert(record, at: 0)
        if records.count > 60, let last = records.last, last.finished { records.removeLast() }
        if let window { owners[ObjectIdentifier(download)] = window }
        download.delegate = self
        record.observation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        changed()
    }
    private func record(_ download: WKDownload) -> DownloadRecord? { records.first { $0.download === download } }
    private func changed() {
        guard !changePending else { return }; changePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.changePending = false
            NotificationCenter.default.post(name: .linuxDoDownloadsChanged, object: nil)
        }
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let record = record(download) else { completionHandler(nil); return }
        record.name = safeDownloadName(suggestedFilename)
        let directory: URL
        if AppConfig.preview {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("LinuxDo-preview-downloads", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } else { directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
        let reserved = Set(records.compactMap(\.destination))
        let destination = uniqueDownloadURL(directory: directory, filename: record.name, reserved: reserved)
        let finish: (URL?) -> Void = { [weak self, weak record] url in
            record?.destination = url
            if url == nil { record?.finished = true; record?.state = "已取消"; record?.observation = nil }
            else { record?.name = url!.lastPathComponent }
            completionHandler(url); self?.changed()
        }
        if Prefs.defaults.bool(forKey: Prefs.downloadAsk), let window = owners[ObjectIdentifier(download)], window.isVisible {
            let panel = NSSavePanel(); panel.nameFieldStringValue = record.name; panel.directoryURL = directory
            panel.beginSheetModal(for: window) { response in finish(response == .OK ? panel.url : nil) }
        } else { finish(destination) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let r = record(download) else { return }
        r.finished = true; r.succeeded = true; r.state = "下载完成"; r.observation = nil
        owners.removeValue(forKey: ObjectIdentifier(download)); changed()
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let r = record(download) else { return }
        if r.state != "已取消" { r.state = "下载失败：\(error.localizedDescription)" }
        r.finished = true; r.observation = nil
        owners.removeValue(forKey: ObjectIdentifier(download)); changed()
    }
    func cancel(id: UUID) {
        guard let r = records.first(where: { $0.id == id }), !r.finished else { return }
        r.state = "已取消"; r.finished = true; r.observation = nil
        r.download.cancel { [weak self] _ in self?.changed() }
        owners.removeValue(forKey: ObjectIdentifier(r.download)); changed()
    }
    func clearFinished() { records.removeAll { $0.finished }; changed() }
}

final class DownloadsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let empty = textLabel("下载会显示在这里", size: 13, secondary: true)
    private var token: NSObjectProtocol?
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 350))
        let title = textLabel("下载", size: 17, weight: .semibold)
        let clear = NSButton(title: "清除已完成", target: self, action: #selector(clearFinished)); clear.bezelStyle = .inline
        let top = NSStackView(views: [title, NSView(), clear]); top.spacing = 12
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        table.headerView = nil; table.style = .inset; table.rowHeight = 76
        table.addTableColumn(NSTableColumn(identifier: .init("download")))
        table.dataSource = self; table.delegate = self; table.allowsEmptySelection = true
        table.setAccessibilityLabel("下载列表"); scroll.documentView = table
        for v in [top, scroll, empty] { view.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([top.topAnchor.constraint(equalTo: view.topAnchor, constant: 18), top.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 16), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8), empty.centerXAnchor.constraint(equalTo: view.centerXAnchor), empty.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        token = NotificationCenter.default.addObserver(forName: .linuxDoDownloadsChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    private func refresh() { table.reloadData(); empty.isHidden = !DownloadManager.shared.records.isEmpty }
    @objc private func clearFinished() { DownloadManager.shared.clearFinished() }
    func numberOfRows(in tableView: NSTableView) -> Int { DownloadManager.shared.records.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = DownloadManager.shared.records[row], cell = NSView()
        let name = textLabel(r.name, size: 13, weight: .medium); name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = textLabel(r.status, size: 11, secondary: true); status.lineBreakMode = .byTruncatingTail
        let progress = NSProgressIndicator(); progress.style = .bar; progress.isIndeterminate = r.download.progress.totalUnitCount <= 0 && !r.finished
        progress.minValue = 0; progress.maxValue = 1; progress.doubleValue = r.succeeded ? 1 : r.fraction
        if progress.isIndeterminate { progress.startAnimation(nil) }
        let text = NSStackView(views: [name, status, progress]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 5
        progress.translatesAutoresizingMaskIntoConstraints = false; progress.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        let action = symbolButton(r.succeeded ? "magnifyingglass" : "xmark.circle", r.succeeded ? "在 Finder 中显示" : "取消下载", target: self, action: #selector(recordAction(_:)))
        action.identifier = NSUserInterfaceItemIdentifier(r.id.uuidString); action.bezelStyle = .inline
        action.isHidden = r.finished && !r.succeeded
        cell.addSubview(text); cell.addSubview(action); text.translatesAutoresizingMaskIntoConstraints = false; action.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), text.trailingAnchor.constraint(equalTo: action.leadingAnchor, constant: -12), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor), action.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), action.centerYAnchor.constraint(equalTo: cell.centerYAnchor), action.widthAnchor.constraint(equalToConstant: 26)])
        return cell
    }
    @objc private func recordAction(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let r = DownloadManager.shared.records.first(where: { $0.id.uuidString == id }) else { return }
        if r.succeeded, let url = r.destination { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { DownloadManager.shared.cancel(id: r.id) }
    }
}
