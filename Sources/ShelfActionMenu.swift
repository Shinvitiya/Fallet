import AppKit

struct ShelfActionOption {
    let title: String
    let detail: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, detail: String, symbol: String, enabled: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.enabled = enabled
        self.action = action
    }
}

private final class ShelfActionRow: NSButton {
    private let callback: () -> Void
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, option: ShelfActionOption, onSelect: @escaping (() -> Void) -> Void) {
        callback = { onSelect(option.action) }
        super.init(frame: frame)
        title = ""
        isBordered = false
        isEnabled = option.enabled
        setAccessibilityLabel(option.title)
        setAccessibilityHelp(option.detail)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor

        let iconWell = NSView(frame: NSRect(x: 10, y: 9, width: 30, height: 30))
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 9
        iconWell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        addSubview(iconWell)
        let icon = NSImageView(frame: NSRect(x: 6, y: 6, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: option.symbol, accessibilityDescription: option.title)
        icon.contentTintColor = .white
        iconWell.addSubview(icon)

        let title = NSTextField(labelWithString: option.title)
        title.frame = NSRect(x: 49, y: 8, width: 189, height: 16)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = option.enabled ? .white : NSColor.white.withAlphaComponent(0.4)
        addSubview(title)
        let detail = NSTextField(labelWithString: option.detail)
        detail.frame = NSRect(x: 49, y: 26, width: 194, height: 14)
        detail.font = .systemFont(ofSize: 9)
        detail.textColor = NSColor.white.withAlphaComponent(option.enabled ? 0.57 : 0.3)
        detail.lineBreakMode = .byTruncatingTail
        addSubview(detail)
        let arrow = NSImageView(frame: NSRect(x: frame.width - 24, y: 17, width: 11, height: 11))
        arrow.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        arrow.contentTintColor = NSColor.white.withAlphaComponent(0.58)
        addSubview(arrow)
        target = self
        action = #selector(selected)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.17).cgColor }
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor
    }

    @objc private func selected() { callback() }
}

private final class ShelfActionMenuView: NSView {
    let titles: (String, String)
    let groups: ([ShelfActionOption], [ShelfActionOption])
    let singleList: Bool
    let onSelect: (() -> Void) -> Void
    private var selectedGroup = 0
    private let backdrop = NSVisualEffectView()

    init(titles: (String, String), groups: ([ShelfActionOption], [ShelfActionOption]), singleList: Bool,
         onSelect: @escaping (() -> Void) -> Void) {
        self.titles = titles
        self.groups = groups
        self.singleList = singleList
        self.onSelect = onSelect
        let rows = singleList ? groups.0.count : max(groups.0.count, groups.1.count)
        super.init(frame: NSRect(x: 0, y: 0, width: 296,
                                 height: (singleList ? 28 : 74) + CGFloat(rows) * 52))
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        backdrop.frame = bounds
        backdrop.autoresizingMask = [.width, .height]
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 18
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func rebuild() {
        let options = selectedGroup == 0 ? groups.0 : groups.1
        let height = frame.height
        for subview in subviews where subview !== backdrop { subview.removeFromSuperview() }

        let tint = NSView(frame: bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0.19, alpha: 0.61).cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(0.23).cgColor
        tint.layer?.cornerRadius = 18
        addSubview(tint)

        if !singleList {
            let tabs = NSView(frame: NSRect(x: 12, y: height - 48, width: 272, height: 33))
            tabs.wantsLayer = true
            tabs.layer?.cornerRadius = 11
            tabs.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
            addSubview(tabs)
            for index in 0...1 {
                let tab = NSButton(frame: NSRect(x: CGFloat(index) * 136 + 2, y: 3, width: 132, height: 27))
                tab.title = index == 0 ? titles.0 : titles.1
                tab.font = .systemFont(ofSize: 10, weight: .semibold)
                tab.isBordered = false
                tab.contentTintColor = .white
                tab.wantsLayer = true
                tab.layer?.cornerRadius = 9
                tab.layer?.backgroundColor = NSColor.white.withAlphaComponent(index == selectedGroup ? 0.22 : 0.02).cgColor
                tab.tag = index
                tab.target = self
                tab.action = #selector(switchTab(_:))
                tabs.addSubview(tab)
            }
        }

        for (index, option) in options.enumerated() {
            let row = ShelfActionRow(frame: NSRect(x: 12, y: height - (singleList ? 58 : 106) - CGFloat(index) * 52,
                                              width: 272, height: 46), option: option,
                                     onSelect: onSelect)
            addSubview(row)
        }
    }

    @objc private func switchTab(_ sender: NSButton) {
        selectedGroup = sender.tag
        rebuild()
    }
}

final class ShelfActionPopover {
    private var popover: NSPopover?

    func show(from anchor: NSView, titles: (String, String),
              groups: ([ShelfActionOption], [ShelfActionOption]), singleList: Bool = false) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !ShelfGlassStyle.reduceMotion
        popover.appearance = NSAppearance(named: .darkAqua)
        let controller = NSViewController()
        let view = ShelfActionMenuView(titles: titles, groups: groups, singleList: singleList) { [weak popover] callback in
            popover?.close()
            callback()
        }
        controller.view = view
        popover.contentViewController = controller
        popover.contentSize = view.frame.size
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        self.popover = popover
    }
}
