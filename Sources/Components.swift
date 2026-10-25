import Cocoa

func symbolButton(_ symbol: String, _ title: String, target: AnyObject?, action: Selector?) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: target, action: action)
    button.bezelStyle = .texturedRounded
    button.toolTip = title
    button.setAccessibilityLabel(title)
    return button
}

func textLabel(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    if secondary { label.textColor = .secondaryLabelColor }
    return label
}

func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
}

final class ProgressLine: NSView {
    private let bar = CALayer()
    private var current = 0.0
    private var generation = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bar.backgroundColor = AppConfig.brandGold.cgColor
        bar.anchorPoint = .zero
        bar.opacity = 0
        layer?.addSublayer(bar)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(progress: Double, loading: Bool) {
        generation += 1
        let token = generation
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        current = loading ? max(0.04, min(progress, 1)) : 1
        CATransaction.begin()
        CATransaction.setAnimationDuration(reduce ? 0 : 0.18)
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width * current, height: bounds.height)
        bar.opacity = loading ? 1 : bar.opacity
        CATransaction.commit()
        if !loading {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                guard let self, token == self.generation else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(reduce ? 0 : 0.18)
                self.bar.opacity = 0
                CATransaction.commit()
            }
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width * current, height: bounds.height)
        CATransaction.commit()
    }
}

final class ErrorOverlay: NSView {
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    let retryButton = NSButton(title: "重新加载", target: nil, action: nil)
    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView(image: NSImage(systemSymbolName: "wifi.exclamationmark", accessibilityDescription: "连接中断")!)
        icon.symbolConfiguration = .init(pointSize: 36, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.preferredMaxLayoutWidth = 380
        retryButton.bezelStyle = .rounded
        let stack = NSStackView(views: [icon, textLabel("暂时没有连接上", size: 22, weight: .semibold), messageLabel, retryButton])
        stack.orientation = .vertical; stack.spacing = 16
        addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420)])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A single glass surface for a temporary control, never under the reading content.
final class FloatingNotice: NSView {
    let label = textLabel("", size: 12)
    let actionButton = NSButton(title: "重试", target: nil, action: nil)
    let dismissButton = symbolButton("xmark", "关闭提示", target: nil, action: nil)
    private var materialView: NSView?
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        rebuildMaterial()
    }
    required init?(coder: NSCoder) { fatalError() }
    func rebuildMaterial() {
        materialView?.removeFromSuperview()
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.bezelStyle = .rounded; actionButton.controlSize = .small
        dismissButton.bezelStyle = .inline; dismissButton.controlSize = .small
        let stack = NSStackView(views: [label, actionButton, dismissButton]); stack.spacing = 10
        let content = NSView(); content.addSubview(stack); pin(stack, to: content, inset: 12)
        let surface: NSView
        if #available(macOS 26.0, *), Prefs.defaults.bool(forKey: Prefs.glass), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass = NSGlassEffectView(); glass.style = .regular; glass.cornerRadius = 18
            glass.contentView = content; surface = glass
            pin(content, to: glass)
        } else {
            let effect = NSVisualEffectView(); effect.material = .popover; effect.blendingMode = .withinWindow
            effect.wantsLayer = true; effect.layer?.cornerRadius = 12
            effect.addSubview(content); pin(content, to: effect); surface = effect
        }
        addSubview(surface); pin(surface, to: self); materialView = surface
    }
}

final class FindBar: NSView {
    let field = NSSearchField()
    let status = textLabel("", size: 11, secondary: true)
    let previous = symbolButton("chevron.up", "上一个匹配（⇧⌘G）", target: nil, action: nil)
    let next = symbolButton("chevron.down", "下一个匹配（⌘G）", target: nil, action: nil)
    let done = NSButton(title: "完成", target: nil, action: nil)
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = "在当前页面查找"
        field.setAccessibilityLabel("页内查找")
        done.bezelStyle = .rounded
        let row = NSStackView(views: [field, status, previous, next, done]); row.spacing = 8
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), row.centerYAnchor.constraint(equalTo: centerYAnchor), field.widthAnchor.constraint(equalToConstant: 240)])
    }
    required init?(coder: NSCoder) { fatalError() }
}
