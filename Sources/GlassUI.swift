import AppKit
import QuartzCore

enum ShelfGlassStyle {
    static let primaryText = NSColor(calibratedWhite: 1, alpha: 0.96)
    static let secondaryText = NSColor(calibratedWhite: 1, alpha: 0.57)
    static let rowFill = NSColor(calibratedWhite: 1, alpha: 0.085)
    static let rowBorder = NSColor(calibratedWhite: 1, alpha: 0.12)

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func animateColor(on layer: CALayer?, keyPath: String, to color: CGColor, duration: CFTimeInterval = 0.18) {
        guard let layer else { return }
        if !reduceMotion {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
            animation.toValue = color
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: keyPath)
        }
        layer.setValue(color, forKeyPath: keyPath)
    }
}

final class GlassBackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class GlassDecorationView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class GlassOverlayView: NSView {
    var isDropTarget = false { didSet { needsDisplay = true } }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
        NSColor(calibratedWhite: 0.72, alpha: 0.24).setFill()
        shape.fill()
        if let sheen = NSGradient(starting: NSColor(calibratedWhite: 1, alpha: 0.10),
                                  ending: NSColor(calibratedWhite: 1, alpha: 0.005)) {
            sheen.draw(in: shape, angle: -90)
        }
        shape.lineWidth = isDropTarget ? 2.5 : 1
        (isDropTarget ? NSColor.systemBlue.withAlphaComponent(0.95)
                      : NSColor(calibratedWhite: 1, alpha: 0.31)).setStroke()
        shape.stroke()

        let top = NSBezierPath()
        top.move(to: NSPoint(x: 27, y: bounds.maxY - 1.5))
        top.line(to: NSPoint(x: bounds.maxX - 27, y: bounds.maxY - 1.5))
        top.lineWidth = 1
        NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
        top.stroke()
    }
}

final class GlassPillButton: NSButton {
    private let prominent: Bool
    private var isHovered = false
    private var isPressed = false
    private var hoverArea: NSTrackingArea?

    init(frame: NSRect, title: String, symbol: String, prominent: Bool = false) {
        self.prominent = prominent
        super.init(frame: frame)
        self.title = title
        isBordered = false
        focusRingType = .none
        font = .systemFont(ofSize: 11, weight: .semibold)
        alignment = .center
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title.isEmpty ? symbol : title)
        imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        imageHugsTitle = true
        contentTintColor = ShelfGlassStyle.primaryText
        wantsLayer = true
        layer?.cornerRadius = min(frame.height / 2, 18)
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance(animated: true)
        super.mouseDown(with: event)
        isPressed = false
        updateAppearance(animated: true)
    }

    private func updateAppearance(animated: Bool) {
        let fill: NSColor
        if prominent {
            fill = NSColor(calibratedWhite: isPressed ? 0.22 : (isHovered ? 0.14 : 0.045), alpha: 0.95)
        } else {
            fill = NSColor(calibratedWhite: 1, alpha: isPressed ? 0.24 : (isHovered ? 0.18 : 0.11))
        }
        let border = NSColor(calibratedWhite: 1, alpha: isPressed ? 0.37 : (isHovered ? 0.27 : 0.16))
        if animated {
            ShelfGlassStyle.animateColor(on: layer, keyPath: "backgroundColor", to: fill.cgColor)
            ShelfGlassStyle.animateColor(on: layer, keyPath: "borderColor", to: border.cgColor)
        } else {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = border.cgColor
        }
    }
}

final class DragAllFilesView: DragFilesView {
    enum State { case ready, hint, dragging, success }

    private let symbolView = NSImageView()
    private let titleView = NSTextField(labelWithString: "")
    private var state: State = .ready
    private var count = 0
    private var isPressed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        symbolView.frame = NSRect(x: 13, y: 10, width: 17, height: 17)
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = ShelfGlassStyle.primaryText
        symbolView.wantsLayer = true
        addSubview(symbolView)

        titleView.frame = NSRect(x: 36, y: 10, width: frame.width - 44, height: 17)
        titleView.font = .systemFont(ofSize: 11, weight: .semibold)
        titleView.textColor = ShelfGlassStyle.primaryText
        titleView.lineBreakMode = .byTruncatingTail
        titleView.wantsLayer = true
        addSubview(titleView)
        applyState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setState(_ newState: State, count: Int, animated: Bool = true) {
        state = newState
        self.count = count
        applyState(animated: animated)
    }

    func setPressed(_ pressed: Bool) {
        isPressed = pressed
        applyState(animated: true)
    }

    private func applyState(animated: Bool) {
        let symbol: String
        let title: String
        let fill: NSColor
        let border: NSColor
        switch state {
        case .ready:
            symbol = "arrow.up.right"
            title = "Drag all \(count)"
            fill = NSColor(calibratedWhite: isPressed ? 0.19 : 0.02, alpha: 0.91)
            border = NSColor(calibratedWhite: 1, alpha: isPressed ? 0.42 : 0.23)
        case .hint:
            symbol = "hand.point.up.left"
            title = "Hold & drag"
            fill = NSColor(calibratedWhite: 1, alpha: isPressed ? 0.27 : 0.18)
            border = NSColor(calibratedWhite: 1, alpha: 0.38)
        case .dragging:
            symbol = "arrow.up.right"
            title = "Drop in Finder"
            fill = NSColor.systemBlue.withAlphaComponent(0.9)
            border = NSColor(calibratedWhite: 1, alpha: 0.52)
        case .success:
            symbol = "checkmark.circle.fill"
            title = "Moved \(count) \(count == 1 ? "file" : "files")"
            fill = NSColor.systemGreen.withAlphaComponent(0.93)
            border = NSColor(calibratedWhite: 1, alpha: 0.38)
        }

        if animated && !ShelfGlassStyle.reduceMotion {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            symbolView.layer?.add(transition, forKey: "symbolChange")
            titleView.layer?.add(transition, forKey: "titleChange")
            ShelfGlassStyle.animateColor(on: layer, keyPath: "backgroundColor", to: fill.cgColor, duration: 0.22)
            ShelfGlassStyle.animateColor(on: layer, keyPath: "borderColor", to: border.cgColor, duration: 0.22)
        } else {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = border.cgColor
        }
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        titleView.stringValue = title
        toolTip = state == .ready ? "Hold and drag to a Finder folder to move all files" : title
    }
}
