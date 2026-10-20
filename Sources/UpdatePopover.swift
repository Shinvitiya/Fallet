import AppKit

private final class UpdateNoticeView: NSView {
    private let onViewRelease: () -> Void
    private let copyButton: GlassPillButton

    init(update: AvailableUpdate, onViewRelease: @escaping () -> Void) {
        self.onViewRelease = onViewRelease
        copyButton = GlassPillButton(frame: NSRect(x: 165, y: 17, width: 139, height: 34),
                                      title: "Copy command", symbol: "doc.on.doc")
        super.init(frame: NSRect(x: 0, y: 0, width: 318, height: 198))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true

        let glass = NSVisualEffectView(frame: bounds)
        glass.autoresizingMask = [.width, .height]
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        addSubview(glass)
        let tint = GlassDecorationView(frame: bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0.19, alpha: 0.61).cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(0.23).cgColor
        tint.layer?.cornerRadius = 18
        addSubview(tint)

        addSubview(Self.label("Update available", frame: NSRect(x: 17, y: 157, width: 270, height: 23),
                              size: 15, weight: .semibold))
        addSubview(Self.label("A newer Fallet (v\(update.release.version)) is available.",
                              frame: NSRect(x: 17, y: 129, width: 285, height: 18), size: 11))
        addSubview(Self.label("Installed version: v\(update.installedVersion)",
                              frame: NSRect(x: 17, y: 108, width: 285, height: 17), size: 10,
                              color: ShelfGlassStyle.secondaryText))
        addSubview(Self.label("Homebrew: brew upgrade fallet",
                              frame: NSRect(x: 17, y: 82, width: 285, height: 18), size: 10,
                              color: ShelfGlassStyle.secondaryText))
        addSubview(Self.label("Other installs: view release details on GitHub.",
                              frame: NSRect(x: 17, y: 64, width: 285, height: 18), size: 10,
                              color: ShelfGlassStyle.secondaryText))

        let releaseButton = GlassPillButton(frame: NSRect(x: 14, y: 17, width: 143, height: 34),
                                            title: "View release", symbol: "arrow.up.right.square")
        releaseButton.target = self
        releaseButton.action = #selector(viewRelease)
        addSubview(releaseButton)
        copyButton.target = self
        copyButton.action = #selector(copyCommand)
        copyButton.toolTip = "Copy update command"
        copyButton.setAccessibilityLabel("Copy update command: brew upgrade fallet")
        addSubview(copyButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func label(_ text: String, frame: NSRect, size: CGFloat,
                              weight: NSFont.Weight = .regular,
                              color: NSColor = ShelfGlassStyle.primaryText) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    @objc private func viewRelease() { onViewRelease() }

    @objc private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew upgrade fallet", forType: .string)
        copyButton.title = "Copied"
    }
}

final class UpdatePopover {
    private var popover: NSPopover?

    func show(_ update: AvailableUpdate, from anchor: NSView) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !ShelfGlassStyle.reduceMotion
        popover.appearance = NSAppearance(named: .darkAqua)
        let controller = NSViewController()
        controller.view = UpdateNoticeView(update: update) { [weak popover] in
            popover?.close()
            NSWorkspace.shared.open(update.release.url)
        }
        popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        self.popover = popover
    }
}
