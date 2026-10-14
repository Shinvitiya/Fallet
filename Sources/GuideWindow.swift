import AppKit
import QuartzCore

private struct GuidePage {
    let eyebrow: String
    let title: String
    let summary: String
    let firstStep: String
    let secondStep: String
}

private let guidePages: [GuidePage] = [
    GuidePage(
        eyebrow: "01  •  COLLECT",
        title: "Give your files a place to wait.",
        summary: "Open the shelf either way, then drag files into it from Finder. Use + if you prefer a file picker.",
        firstStep: "Click the Fallet icon.",
        secondStep: "Shake pointer while dragging in Finder."
    ),
    GuidePage(
        eyebrow: "02  •  SPLIT A BATCH",
        title: "One selection. Many destinations.",
        summary: "Put several files from one folder on the shelf, then send each one exactly where it belongs.",
        firstStep: "Drag File A from the shelf into Folder X in Finder.",
        secondStep: "Drag File B into Folder Y. The other files stay on the shelf."
    ),
    GuidePage(
        eyebrow: "03  •  MOVE TOGETHER",
        title: "Move the whole batch at once.",
        summary: "When every file belongs in the same place, take them all in one drag.",
        firstStep: "Hold and drag Drag all onto a Finder folder.",
        secondStep: "Or choose Move to and pick a destination folder."
    ),
    GuidePage(
        eyebrow: "04  •  STAY IN FLOW",
        title: "A shelf that stays out of your way.",
        summary: "Keep the shelf where you want it, and bring it back only when you need it.",
        firstStep: "Drag its header to reposition it; use − to hide it.",
        secondStep: "Use the menu bar icon to reopen it. Clear only empties the shelf."
    )
]

private final class GuideBackdropView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 0.96).setFill()
        outer.fill()

        NSGraphicsContext.saveGraphicsState()
        outer.addClip()
        let hero = NSRect(x: 0, y: bounds.height - 215, width: bounds.width, height: 215)
        NSGradient(starting: NSColor(calibratedRed: 0.29, green: 0.13, blue: 0.12, alpha: 0.95),
                   ending: NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.30, alpha: 0.95))?
            .draw(in: hero, angle: 0)
        NSGradient(starting: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1),
                   ending: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 0))?
            .draw(in: NSRect(x: 0, y: bounds.height - 215, width: bounds.width, height: 100), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
        outer.lineWidth = 1
        outer.stroke()
    }
}

private final class GuideDiagramView: NSView {
    var page = 0 { didSet { rebuildTiles(); needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        rebuildTiles()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 1, alpha: 0.025).setFill()
        card.fill()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
        card.lineWidth = 1
        card.stroke()

        switch page {
        case 0:
            arrow(from: 148, to: 202, y: 93)
            arrow(from: 300, to: 354, y: 93)
        case 1:
            arrow(from: 217, to: 298, y: 112)
            arrow(from: 217, to: 298, y: 46)
        case 2:
            arrow(from: 190, to: 321, y: 94)
        default:
            break
        }
    }

    private func rebuildTiles() {
        subviews.forEach { $0.removeFromSuperview() }
        switch page {
        case 0:
            iconTile("doc.on.doc", label: "Finder", frame: NSRect(x: 61, y: 57, width: 72, height: 72))
            iconTile("square.grid.3x3.fill", label: "Fallet", frame: NSRect(x: 214, y: 57, width: 72, height: 72), active: true)
            iconTile("folder", label: "Folders", frame: NSRect(x: 367, y: 57, width: 72, height: 72))
        case 1:
            compactTile("doc.text", label: "File A", frame: NSRect(x: 31, y: 88, width: 48, height: 48), active: true)
            compactTile("folder", label: "Folder X", frame: NSRect(x: 308, y: 88, width: 48, height: 48))
            compactTile("doc", label: "File B", frame: NSRect(x: 31, y: 22, width: 48, height: 48), active: true)
            compactTile("folder", label: "Folder Y", frame: NSRect(x: 308, y: 22, width: 48, height: 48))
        case 2:
            iconTile("square.stack.3d.up", label: "Drag all 10", frame: NSRect(x: 99, y: 58, width: 72, height: 72), active: true)
            iconTile("folder", label: "Destination", frame: NSRect(x: 329, y: 58, width: 72, height: 72))
            let note = caption("Move to also opens a folder picker", frame: NSRect(x: 90, y: 10, width: 320, height: 16), active: false)
            note.font = .systemFont(ofSize: 9.5)
            addSubview(note)
        default:
            iconTile("hand.draw", label: "Position", frame: NSRect(x: 31, y: 64, width: 58, height: 58), captionWidth: 100)
            iconTile("minus", label: "Hide", frame: NSRect(x: 157, y: 64, width: 58, height: 58), captionWidth: 100)
            iconTile("menubar.rectangle", label: "Menu bar", frame: NSRect(x: 283, y: 64, width: 58, height: 58), active: true, captionWidth: 100)
            iconTile("xmark", label: "Clear", frame: NSRect(x: 409, y: 64, width: 58, height: 58), captionWidth: 100)
        }
    }

    private func iconTile(_ symbol: String, label: String, frame: NSRect, active: Bool = false, captionWidth: CGFloat = 108) {
        addSubview(iconSquare(symbol, frame: frame, active: active))
        addSubview(caption(label, frame: NSRect(x: frame.midX - captionWidth / 2, y: frame.minY - 25,
                                                width: captionWidth, height: 18), active: active))
    }

    private func compactTile(_ symbol: String, label: String, frame: NSRect, active: Bool = false) {
        addSubview(iconSquare(symbol, frame: frame, active: active))
        let text = caption(label, frame: NSRect(x: frame.maxX + 10, y: frame.minY + 15,
                                                width: 116, height: 20), active: active)
        text.alignment = .left
        text.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(text)
    }

    private func iconSquare(_ symbol: String, frame: NSRect, active: Bool) -> NSView {
        let square = NSView(frame: frame)
        square.wantsLayer = true
        square.layer?.cornerRadius = frame.width * 0.23
        square.layer?.backgroundColor = active
            ? NSColor(calibratedRed: 0.05, green: 0.43, blue: 0.84, alpha: 0.17).cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.035).cgColor
        square.layer?.borderWidth = 1.2
        square.layer?.borderColor = active
            ? NSColor(calibratedRed: 0.17, green: 0.63, blue: 1, alpha: 0.85).cgColor
            : NSColor(calibratedWhite: 1, alpha: 0.22).cgColor
        square.layer?.shadowColor = active ? NSColor.systemBlue.cgColor : NSColor.black.cgColor
        square.layer?.shadowOpacity = active ? 0.16 : 0.08
        square.layer?.shadowRadius = 10
        square.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let inset = frame.width * 0.27
        let icon = NSImageView(frame: NSRect(x: inset, y: inset, width: frame.width - 2 * inset,
                                             height: frame.height - 2 * inset))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "square", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = active
            ? NSColor(calibratedRed: 0.19, green: 0.65, blue: 1, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 0.66)
        square.addSubview(icon)
        return square
    }

    private func caption(_ value: String, frame: NSRect, active: Bool) -> NSTextField {
        let text = NSTextField(labelWithString: value)
        text.frame = frame
        text.alignment = .center
        text.font = .systemFont(ofSize: 10.5, weight: .medium)
        text.textColor = active
            ? NSColor(calibratedRed: 0.40, green: 0.75, blue: 1, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 0.72)
        return text
    }

    private func arrow(from start: CGFloat, to end: CGFloat, y: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: start, y: y))
        path.line(to: NSPoint(x: end - 8, y: y))
        path.lineWidth = 1.3
        path.setLineDash([3, 4], count: 2, phase: 0)
        NSColor(calibratedWhite: 1, alpha: 0.42).setStroke()
        path.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: end - 14, y: y + 5))
        head.line(to: NSPoint(x: end - 8, y: y))
        head.line(to: NSPoint(x: end - 14, y: y - 5))
        head.lineWidth = 1.3
        head.stroke()
    }
}

private final class GuideButton: NSButton {
    private let accent: Bool
    private var hovered = false
    private var trackingAreaRef: NSTrackingArea?

    init(frame: NSRect, title: String, accent: Bool) {
        self.accent = accent
        super.init(frame: frame)
        self.title = title
        font = .systemFont(ofSize: 12, weight: .semibold)
        isBordered = false
        focusRingType = .none
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        layer?.borderWidth = 1
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovered = false; refresh() }

    private func refresh() {
        let fill = accent
            ? NSColor(calibratedRed: hovered ? 0.29 : 0.22, green: hovered ? 0.50 : 0.42, blue: 0.96, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: hovered ? 0.19 : 0.11)
        ShelfGlassStyle.animateColor(on: layer, keyPath: "backgroundColor", to: fill.cgColor)
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: accent ? 0.21 : 0.16).cgColor
    }
}

final class GuideView: NSView {
    private let backdrop = NSVisualEffectView()
    private let decoration = GuideBackdropView()
    private var currentPage = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        addSubview(backdrop)
        decoration.frame = bounds
        decoration.autoresizingMask = [.width, .height]
        addSubview(decoration)
        showPage(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reset() {
        currentPage = 0
        showPage(animated: false)
    }

    private func label(_ value: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .white, alignment: NSTextAlignment = .left) -> NSTextField {
        let view = NSTextField(labelWithString: value)
        view.frame = frame
        view.font = .systemFont(ofSize: size, weight: weight)
        view.textColor = color
        view.alignment = alignment
        view.lineBreakMode = .byWordWrapping
        view.maximumNumberOfLines = 0
        return view
    }

    private func optionCard(title: String, detail: String, frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 11
        card.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.075).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.17).cgColor
        card.addSubview(label(title, frame: NSRect(x: 12, y: 31, width: frame.width - 24, height: 16),
                              size: 11, weight: .semibold))
        card.addSubview(label(detail, frame: NSRect(x: 12, y: 11, width: frame.width - 24, height: 16),
                              size: 10, color: NSColor(calibratedWhite: 1, alpha: 0.75)))
        return card
    }

    private func showPage(animated: Bool) {
        if animated && !ShelfGlassStyle.reduceMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(fade, forKey: "guidePage")
        }
        for view in subviews where view !== backdrop && view !== decoration { view.removeFromSuperview() }
        let page = guidePages[currentPage]
        addSubview(label("\(currentPage + 1) / \(guidePages.count)", frame: NSRect(x: 32, y: 441, width: 43, height: 18),
                         size: 10, weight: .bold, color: NSColor(calibratedWhite: 1, alpha: 0.72)))
        addSubview(label("FALLET  /  GUIDE", frame: NSRect(x: 68, y: 441, width: 320, height: 18),
                         size: 10, weight: .bold, color: NSColor(calibratedWhite: 1, alpha: 0.72)))
        let close = GuideButton(frame: NSRect(x: 462, y: 435, width: 68, height: 29), title: "Close", accent: false)
        close.target = self
        close.action = #selector(closeClicked)
        addSubview(close)
        addSubview(label(page.eyebrow, frame: NSRect(x: 32, y: 408, width: 390, height: 18),
                         size: 10, weight: .bold, color: NSColor(calibratedRed: 0.58, green: 0.75, blue: 1, alpha: 1)))
        addSubview(label(page.title, frame: NSRect(x: 32, y: 370, width: 496, height: 32), size: 22, weight: .bold))
        addSubview(label(page.summary, frame: NSRect(x: 32, y: 329, width: 496, height: 38), size: 11.5,
                         color: NSColor(calibratedWhite: 1, alpha: 0.82)))

        let diagram = GuideDiagramView(frame: NSRect(x: 30, y: currentPage == 0 ? 164 : 157,
                                                     width: 500, height: currentPage == 0 ? 153 : 160))
        diagram.page = currentPage
        addSubview(diagram)

        if currentPage == 0 {
            addSubview(label("HOW TO OPEN THE SHELF", frame: NSRect(x: 30, y: 137, width: 350, height: 16),
                             size: 10, weight: .bold,
                             color: NSColor(calibratedRed: 0.58, green: 0.75, blue: 1, alpha: 1)))
            addSubview(optionCard(title: "Menu bar", detail: page.firstStep,
                                  frame: NSRect(x: 30, y: 76, width: 224, height: 54)))
            addSubview(label("OR", frame: NSRect(x: 265, y: 94, width: 30, height: 18), size: 10,
                             weight: .bold, color: NSColor(calibratedWhite: 1, alpha: 0.56), alignment: .center))
            addSubview(optionCard(title: "While dragging", detail: page.secondStep,
                                  frame: NSRect(x: 306, y: 76, width: 224, height: 54)))
        } else {
            addSubview(label("1", frame: NSRect(x: 32, y: 124, width: 18, height: 20), size: 11, weight: .bold,
                             color: NSColor(calibratedRed: 0.53, green: 0.73, blue: 1, alpha: 1)))
            addSubview(label(page.firstStep, frame: NSRect(x: 53, y: 121, width: 475, height: 23), size: 11,
                             color: NSColor(calibratedWhite: 1, alpha: 0.85)))
            addSubview(label("2", frame: NSRect(x: 32, y: 95, width: 18, height: 20), size: 11, weight: .bold,
                             color: NSColor(calibratedRed: 0.53, green: 0.73, blue: 1, alpha: 1)))
            addSubview(label(page.secondStep, frame: NSRect(x: 53, y: 92, width: 475, height: 23), size: 11,
                             color: NSColor(calibratedWhite: 1, alpha: 0.85)))
        }

        if currentPage > 0 {
            let back = GuideButton(frame: NSRect(x: 30, y: 20, width: 82, height: 36), title: "Back", accent: false)
            back.target = self
            back.action = #selector(backClicked)
            addSubview(back)
        }

        for index in guidePages.indices {
            let width: CGFloat = index == currentPage ? 15 : 6
            let slotX = 240 + CGFloat(index) * 20
            let dot = NSView(frame: NSRect(x: slotX + (20 - width) / 2, y: 35, width: width, height: 6))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: index == currentPage ? 0.95 : 0.3).cgColor
            addSubview(dot)
        }

        let next = GuideButton(frame: NSRect(x: 426, y: 20, width: 104, height: 36),
                               title: currentPage == guidePages.count - 1 ? "Done" : "Continue", accent: true)
        next.target = self
        next.action = #selector(nextClicked)
        addSubview(next)
    }

    @objc private func backClicked() {
        guard currentPage > 0 else { return }
        currentPage -= 1
        showPage(animated: true)
    }

    @objc private func closeClicked() { window?.close() }

    @objc private func nextClicked() {
        if currentPage == guidePages.count - 1 { window?.close() }
        else { currentPage += 1; showPage(animated: true) }
    }
}

final class GuideWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        title = "How to use Fallet"
        isMovableByWindowBackground = true
        isFloatingPanel = true
        isReleasedWhenClosed = false
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        contentView = GuideView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }

    func resetGuide() { (contentView as? GuideView)?.reset() }
}
