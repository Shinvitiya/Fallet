import AppKit

final class ContentEntryWindow: NSPanel {
    private let field = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let onSubmit: (String) -> String?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(kind: ShelfEntryKind, onSubmit: @escaping (String) -> String?) {
        self.onSubmit = onSubmit
        let frame = NSRect(x: 0, y: 0, width: 340, height: 176)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        let root = NSView(frame: frame)
        root.wantsLayer = true
        root.layer?.cornerRadius = 22
        root.layer?.masksToBounds = true
        contentView = root

        let blur = NSVisualEffectView(frame: root.bounds)
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        root.addSubview(blur)
        root.addSubview(GlassOverlayView(frame: root.bounds))

        let heading = NSTextField(labelWithString: kind == .link ? "Add a link" : "Add text")
        heading.frame = NSRect(x: 20, y: 139, width: 300, height: 24)
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = ShelfGlassStyle.primaryText
        root.addSubview(heading)

        let explanation = NSTextField(labelWithString: kind == .link
            ? "Paste or type a web address."
            : "Paste or type a note for the shelf.")
        explanation.frame = NSRect(x: 20, y: 117, width: 300, height: 16)
        explanation.font = .systemFont(ofSize: 10.5)
        explanation.textColor = ShelfGlassStyle.secondaryText
        root.addSubview(explanation)

        let fieldWell = NSView(frame: NSRect(x: 19, y: 65, width: 302, height: 43))
        fieldWell.wantsLayer = true
        fieldWell.layer?.cornerRadius = 12
        fieldWell.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.19).cgColor
        fieldWell.layer?.borderWidth = 1
        fieldWell.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
        root.addSubview(fieldWell)

        field.frame = NSRect(x: 12, y: 10, width: 278, height: 22)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.focusRingType = .none
        field.placeholderString = kind == .link ? "https://example.com" : "Add a note…"
        fieldWell.addSubview(field)

        errorLabel.frame = NSRect(x: 20, y: 46, width: 300, height: 14)
        errorLabel.font = .systemFont(ofSize: 10)
        errorLabel.textColor = NSColor(calibratedRed: 1, green: 0.55, blue: 0.52, alpha: 1)
        root.addSubview(errorLabel)

        let cancel = GlassPillButton(frame: NSRect(x: 157, y: 11, width: 75, height: 32),
                                     title: "Cancel", symbol: "")
        cancel.target = self
        cancel.action = #selector(cancelClicked)
        cancel.keyEquivalent = "\u{1b}"
        root.addSubview(cancel)
        let add = GlassPillButton(frame: NSRect(x: 239, y: 11, width: 82, height: 32),
                                  title: kind == .link ? "Add link" : "Add text", symbol: "", prominent: true)
        add.target = self
        add.action = #selector(addClicked)
        add.keyEquivalent = "\r"
        root.addSubview(add)
    }

    func present(above shelf: NSWindow?) {
        if let shelf {
            let point = NSPoint(x: shelf.frame.midX - frame.width / 2,
                                y: shelf.frame.midY - frame.height / 2)
            setFrameOrigin(point)
        } else {
            center()
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, let editor = firstResponder as? NSTextView {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": editor.paste(nil); return true
            case "c": editor.copy(nil); return true
            case "x": editor.cut(nil); return true
            case "a": editor.selectAll(nil); return true
            case "z": editor.undoManager?.undo(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func cancelClicked() { close() }

    @objc private func addClicked() {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = onSubmit(value) {
            errorLabel.stringValue = message
            makeFirstResponder(field)
        } else {
            close()
        }
    }
}
