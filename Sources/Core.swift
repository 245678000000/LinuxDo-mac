import Cocoa
import WebKit

// Keep this identifier and the legacy keys: upgrading must retain the existing website store.
enum AppConfig {
    static let appName = "LinuxDo"
    static let homeURL = URL(string: "https://linux.do")!
    static let windowSize = NSSize(width: 1280, height: 840)
    static let legacyUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    static let defaultProxy = "http://127.0.0.1:7890"
    static let brandGold = NSColor(srgbRed: 0.79, green: 0.56, blue: 0.12, alpha: 1)
    static let preview = CommandLine.arguments.contains("--preview")
    static var previewURL: URL { Bundle.main.url(forResource: "Preview", withExtension: "html")! }
    static func isInternal(_ url: URL?) -> Bool {
        guard let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return false }
        return host == "linux.do" || host.hasSuffix(".linux.do")
    }
    static func isPreview(_ url: URL?) -> Bool {
        guard preview, let url, url.isFileURL else { return false }
        return url.standardizedFileURL.path == previewURL.standardizedFileURL.path
    }
    static func route(_ path: String) -> URL {
        if preview {
            var components = URLComponents(url: previewURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "route", value: path)]
            return components.url!
        }
        return URL(string: path, relativeTo: homeURL)!.absoluteURL
    }
    static func searchURL(_ query: String) -> URL {
        var c = URLComponents(url: route("/search"), resolvingAgainstBaseURL: false)!
        var items = c.queryItems ?? []
        items.append(URLQueryItem(name: "q", value: query))
        c.queryItems = items
        return c.url!
    }
}

enum Prefs {
    static let lastURL = "LastURL", pageZoom = "PageZoom", proxyEnabled = "ProxyEnabled", proxyURL = "ProxyURL"
    static let appearance = "NativeAppearance", reading = "ReadingEnhancement", fontSize = "ReadingFontSize"
    static let lineHeight = "ReadingLineHeight", hideWebSidebar = "NativeSidebarIntegration"
    static let sidebarCollapsed = "NativeSidebarCollapsed", compatibilityUA = "CompatibilityUserAgent"
    static let restoreReading = "RestoreReadingPosition", positions = "ReadingPositions"
    static let glass = "NativeGlass", downloadAsk = "AskDownloadLocation"
    static let all: [String] = [appearance, reading, fontSize, lineHeight, hideWebSidebar, sidebarCollapsed, compatibilityUA, restoreReading, glass, downloadAsk]
    static let defaults: UserDefaults = {
        let d = AppConfig.preview ? UserDefaults(suiteName: "com.pake.acea3c3.preview")! : .standard
        d.register(defaults: [appearance: "system", reading: true, fontSize: 16, lineHeight: 1.75,
                             hideWebSidebar: true, "NativeSidebarCollapsedByUser": true, restoreReading: true, glass: true, downloadAsk: false])
        return d
    }()
    static func boundedFont(_ value: Double) -> Double { value.isFinite ? min(22, max(13, value)) : 16 }
    static func boundedLineHeight(_ value: Double) -> Double { value.isFinite ? min(2, max(1.4, value)) : 1.75 }
    static func applyAppearance() {
        switch defaults.string(forKey: appearance) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

extension Notification.Name {
    static let linuxDoPreferencesChanged = Notification.Name("LinuxDoPreferencesChanged")
    static let linuxDoDownloadsChanged = Notification.Name("LinuxDoDownloadsChanged")
}

struct ProxyEndpoint: Equatable {
    let host: String
    let port: UInt16
    let socks: Bool
    static func parse(_ text: String) -> ProxyEndpoint? {
        guard let u = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme?.lowercased(), ["http", "socks5"].contains(scheme),
              let host = u.host, !host.isEmpty, let port = u.port, (1...65535).contains(port),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              u.path.isEmpty || u.path == "/" else { return nil }
        return ProxyEndpoint(host: host, port: UInt16(port), socks: scheme == "socks5")
    }
}

struct PageTitle: Equatable {
    let text: String
    let badge: String?
    static func parse(_ raw: String?) -> PageTitle {
        var title = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var badge: String?
        if title.hasPrefix("("), let close = title.firstIndex(of: ")") {
            let count = String(title[title.index(after: title.startIndex)..<close])
            if count.range(of: #"^[0-9]+\+?$"#, options: .regularExpression) != nil {
                badge = count == "0" ? nil : count
                title = String(title[title.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return PageTitle(text: title.isEmpty ? AppConfig.appName : title, badge: badge)
    }
}

struct ReadingPosition: Codable {
    let url: String
    let x: Double
    let y: Double
    let postID: String?
    let offset: Double?
    let updated: Double
    var isValid: Bool { x.isFinite && y.isFinite && x >= 0 && y >= 0 && (offset?.isFinite ?? true) }
}

final class ReadingStore {
    static let shared = ReadingStore()
    private let defaults: UserDefaults
    private(set) var positions: [String: ReadingPosition]
    init(defaults: UserDefaults = Prefs.defaults) {
        self.defaults = defaults
        positions = defaults.data(forKey: Prefs.positions).flatMap { try? JSONDecoder().decode([String: ReadingPosition].self, from: $0) } ?? [:]
    }
    func save(_ position: ReadingPosition) {
        guard position.isValid, AppConfig.isInternal(URL(string: position.url)) || AppConfig.isPreview(URL(string: position.url)) else { return }
        positions[position.url] = position
        if positions.count > 100 {
            positions = Dictionary(uniqueKeysWithValues: positions.values.sorted { $0.updated > $1.updated }.prefix(100).map { ($0.url, $0) })
        }
        if let data = try? JSONEncoder().encode(positions) { defaults.set(data, forKey: Prefs.positions) }
    }
    func position(for url: URL) -> ReadingPosition? { positions[url.absoluteString] }
    func clear() { positions = [:]; defaults.removeObject(forKey: Prefs.positions) }
}

func safeDownloadName(_ suggested: String) -> String {
    let clean = suggested.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? "download"
    let result = clean.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty || result == "." || result == ".." ? "download" : String(result.prefix(200))
}

func uniqueDownloadURL(directory: URL, filename: String, reserved: Set<URL> = [], exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
    let original = directory.appendingPathComponent(safeDownloadName(filename))
    let base = original.deletingPathExtension().lastPathComponent, ext = original.pathExtension
    var result = original, number = 1
    while reserved.contains(result) || exists(result) {
        result = directory.appendingPathComponent(ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
        number += 1
    }
    return result
}

func jsonString(_ object: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .sortedKeys]),
          let value = String(data: data, encoding: .utf8) else { return "null" }
    return value
}
