// 生成 1024×1024 的 macOS 风格应用图标
// 按原版图标（黑 / 白 / 金 三色带圆形徽标）矢量重绘，放在 macOS 标准圆角方形底板上，
// 保证 Retina 屏和 Dock 放大时依然清晰（原版图标最大只有 256px）。
// 用法：swift make_icon.swift <输出路径.png>

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

// 颜色取样自原版 linuxdo_256.ico
let black = NSColor(srgbRed: 0x25 / 255.0, green: 0x25 / 255.0, blue: 0x28 / 255.0, alpha: 1)
let light = NSColor(srgbRed: 0xF3 / 255.0, green: 0xF3 / 255.0, blue: 0xF3 / 255.0, alpha: 1)
let gold = NSColor(srgbRed: 1.0, green: 0xBC / 255.0, blue: 0.0, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 1. 底板：Apple 图标网格 824×824，圆角约 185，带柔和投影
let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let plate = NSBezierPath(roundedRect: plateRect, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.set()
NSColor.white.setFill()
plate.fill()
NSGraphicsContext.restoreGraphicsState()

// 底板渐变（顶部纯白 → 底部浅灰），增加质感
NSGradient(starting: NSColor(white: 1.0, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))!
    .draw(in: plate, angle: -90)
NSColor.black.withAlphaComponent(0.06).setStroke()
plate.lineWidth = 2
plate.stroke()

// 2. 三色带圆形徽标（比例取自原图：黑带占上 27%，金带从 72.2% 开始）
let d: CGFloat = 600
let circleRect = NSRect(x: (size - d) / 2, y: (size - d) / 2, width: d, height: d)
let circle = NSBezierPath(ovalIn: circleRect)

NSGraphicsContext.saveGraphicsState()
let cShadow = NSShadow()
cShadow.shadowOffset = NSSize(width: 0, height: -6)
cShadow.shadowBlurRadius = 14
cShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
cShadow.set()
light.setFill()
circle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
circle.addClip()
let top = circleRect.maxY
black.setFill()
NSRect(x: circleRect.minX, y: top - d * 0.27, width: d, height: d * 0.27).fill()
gold.setFill()
NSRect(x: circleRect.minX, y: circleRect.minY, width: d, height: d * (1 - 0.722)).fill()
NSGraphicsContext.restoreGraphicsState()

// 细描边，让徽标在白色底板上边缘清晰
NSColor.black.withAlphaComponent(0.10).setStroke()
circle.lineWidth = 3
circle.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("图标已生成：\(output)")
