import AppKit
import ClikoCore

/// Icons for the menu bar and the menu: SF Symbols, except PMD. SF Symbols has
/// no bin bag, and a shopping bag reads as groceries, so PMD is a tied bin bag
/// drawn here on the same 24-unit grid SF Symbols uses.
func wasteIcon(_ kind: WasteKind, pointSize: CGFloat) -> NSImage? {
    kind == .pmd ? binBagImage(pointSize: pointSize) : symbolImage(kind.symbolName, pointSize: pointSize)
}

func symbolImage(_ name: String, pointSize: CGFloat) -> NSImage? {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: name)
        ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: name)
    let image = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
    image?.isTemplate = true
    return image
}

/// A tied bin bag, as a template image (macOS tints it like the other menu bar icons).
func binBagImage(pointSize: CGFloat) -> NSImage {
    let side = pointSize * 1.15   // SF Symbols at this point size are about this tall
    let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
        let s = rect.width / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let path = NSBezierPath()
        // Body
        path.move(to: p(10.2, 7.4))
        path.curve(to: p(5, 16.4), controlPoint1: p(6.6, 8.8), controlPoint2: p(4.7, 12.4))
        path.curve(to: p(12, 21), controlPoint1: p(5.3, 19.6), controlPoint2: p(7.9, 21))
        path.curve(to: p(19, 16.4), controlPoint1: p(16.1, 21), controlPoint2: p(18.7, 19.6))
        path.curve(to: p(13.8, 7.4), controlPoint1: p(19.3, 12.4), controlPoint2: p(17.4, 8.8))
        // Tie
        path.move(to: p(9.8, 7.2))
        path.line(to: p(14.2, 7.2))
        // Ears of the knot
        path.move(to: p(11.4, 7))
        path.curve(to: p(8.2, 3.4), controlPoint1: p(10.2, 5.6), controlPoint2: p(8.6, 4.6))
        path.curve(to: p(12, 6.2), controlPoint1: p(9.9, 3.2), controlPoint2: p(11.3, 4.4))
        path.move(to: p(12.6, 7))
        path.curve(to: p(15.8, 3.4), controlPoint1: p(13.8, 5.6), controlPoint2: p(15.4, 4.6))
        path.curve(to: p(12, 6.2), controlPoint1: p(14.1, 3.2), controlPoint2: p(12.7, 4.4))
        // A fold, so it reads as soft plastic
        path.move(to: p(9, 13))
        path.curve(to: p(15, 13), controlPoint1: p(11, 14), controlPoint2: p(13, 14))
        path.lineWidth = 1.7 * s
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.black.setStroke()
        path.stroke()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "PMD"
    return image
}

/// A menu row with an icon, drawn as its own view: plain NSMenuItem images
/// did not show on macOS 26. Rows are information, so they don't highlight.
func iconMenuItem(_ title: String, image: NSImage?) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let icon = NSImageView()
    icon.image = image
    icon.contentTintColor = .labelColor
    icon.imageScaling = .scaleProportionallyDown
    let label = NSTextField(labelWithString: title)
    label.font = .menuFont(ofSize: 0)
    label.textColor = .labelColor
    let row = NSStackView(views: [icon, label])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    row.edgeInsets = NSEdgeInsets(top: 3, left: 14, bottom: 3, right: 16)
    icon.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        icon.widthAnchor.constraint(equalToConstant: 16),
        icon.heightAnchor.constraint(equalToConstant: 16),
    ])
    row.setFrameSize(row.fittingSize)
    row.autoresizingMask = [.width]
    item.view = row
    return item
}
