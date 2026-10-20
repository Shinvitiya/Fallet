import AppKit
import UniformTypeIdentifiers

enum FileMover {
    static func move(_ urls: [URL], to directory: URL) -> (moved: [URL], errors: [String]) {
        var moved: [URL] = []
        var errors: [String] = []
        for source in urls {
            guard FileManager.default.fileExists(atPath: source.path) else {
                errors.append("\(source.lastPathComponent): the original file is missing")
                continue
            }
            var destination = directory.appendingPathComponent(source.lastPathComponent)
            if destination.standardizedFileURL == source.standardizedFileURL { continue }
            if FileManager.default.fileExists(atPath: destination.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                let ext = source.pathExtension
                var index = 2
                repeat {
                    let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                    destination = directory.appendingPathComponent(name)
                    index += 1
                } while FileManager.default.fileExists(atPath: destination.path)
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                moved.append(source)
            } catch {
                errors.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (moved, errors)
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ShelfHeaderView: NSView {
    var onPositionChanged: ((NSPoint) -> Void)?
    private var dragAnchor: NSPoint?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton ? hit : (hit == nil ? nil : self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragAnchor = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragAnchor else { return }
        let pointer = event.locationInWindow
        window.setFrameOrigin(NSPoint(x: window.frame.minX + pointer.x - dragAnchor.x,
                                      y: window.frame.minY + pointer.y - dragAnchor.y))
        onPositionChanged?(NSPoint(x: window.frame.minX, y: window.frame.maxY))
    }

    override func mouseUp(with event: NSEvent) {
        dragAnchor = nil
        if let window {
            onPositionChanged?(NSPoint(x: window.frame.minX, y: window.frame.maxY))
        }
    }
}

class DragFilesView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onMoved: (([URL]) -> Void)?
    var onClick: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragCancelled: (() -> Void)?
    var shouldRemoveMissingURL: ((URL) -> Bool)?
    var showsPressFeedback = false
    private var pendingURLs: [URL] = []
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton ? hit : (hit == nil ? nil : self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragStarted = false
        updatePressFeedback(true)
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = mouseDownEvent != nil && !dragStarted
        mouseDownEvent = nil
        dragStarted = false
        updatePressFeedback(false)
        if wasClick { onClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty, !dragStarted, let mouseDownEvent else { return }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) >= 3 else { return }
        dragStarted = true
        onDragStarted?()
        pendingURLs = urls
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let origin = NSPoint(x: 14 + CGFloat(index % 4) * 5, y: bounds.midY - 16 - CGFloat(index % 4) * 5)
            item.setDraggingFrame(NSRect(origin: origin, size: icon.size), contents: icon)
            return item
        }
        beginDraggingSession(with: items, event: mouseDownEvent, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.move, .copy]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let completed = operation.contains(.move)
            ? pendingURLs
            : pendingURLs.filter {
                !FileManager.default.fileExists(atPath: $0.path) && (shouldRemoveMissingURL?($0) ?? true)
            }
        pendingURLs = []
        mouseDownEvent = nil
        dragStarted = false
        updatePressFeedback(false)
        if completed.isEmpty { onDragCancelled?() }
        else { onMoved?(completed) }
    }

    private func updatePressFeedback(_ pressed: Bool) {
        onPressChanged?(pressed)
        guard showsPressFeedback else { return }
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(pressed ? 0.42 : 0.18).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(pressed ? 0.85 : 0).cgColor
        layer?.borderWidth = pressed ? 1.5 : 0
    }
}

final class FileRowView: DragFilesView {
    private let entry: ShelfEntry
    private let removeAction: (UUID) -> Void
    private let locateAction: (UUID) -> Void

    init(entry: ShelfEntry, status: ShelfEntryStatus, width: CGFloat,
         removeAction: @escaping (UUID) -> Void, locateAction: @escaping (UUID) -> Void) {
        self.entry = entry
        self.removeAction = removeAction
        self.locateAction = locateAction
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 51))
        urls = status == .ready ? [entry.url] : []
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = (status == .ready ? ShelfGlassStyle.rowBorder
                              : NSColor.systemOrange.withAlphaComponent(0.55)).cgColor
        layer?.backgroundColor = ShelfGlassStyle.rowFill.cgColor

        let iconWell = NSView(frame: NSRect(x: 9, y: 7, width: 37, height: 37))
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 10
        iconWell.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.11).cgColor
        addSubview(iconWell)

        let icon = NSImageView(frame: NSRect(x: 5, y: 5, width: 27, height: 27))
        switch status {
        case .ready: icon.image = NSWorkspace.shared.icon(forFile: entry.path)
        case .missing: icon.image = NSImage(systemSymbolName: "questionmark.folder.fill", accessibilityDescription: "Missing source")
        case .volumeUnavailable: icon.image = NSImage(systemSymbolName: "externaldrive.badge.xmark", accessibilityDescription: "Drive disconnected")
        }
        if status != .ready { icon.contentTintColor = .systemOrange }
        icon.imageScaling = .scaleProportionallyUpOrDown
        iconWell.addSubview(icon)

        let name = NSTextField(labelWithString: entry.url.lastPathComponent)
        name.frame = NSRect(x: 56, y: 26, width: width - (status == .ready ? 100 : 171), height: 17)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = ShelfGlassStyle.primaryText
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)

        let detail: String
        switch status {
        case .ready: detail = entry.url.deletingLastPathComponent().lastPathComponent
        case .missing: detail = "Source missing"
        case .volumeUnavailable: detail = "Drive disconnected"
        }
        let folder = NSTextField(labelWithString: detail)
        folder.frame = NSRect(x: 56, y: 9, width: width - (status == .ready ? 100 : 171), height: 15)
        folder.font = .systemFont(ofSize: 10)
        folder.textColor = status == .ready ? ShelfGlassStyle.secondaryText : .systemOrange
        folder.lineBreakMode = .byTruncatingMiddle
        addSubview(folder)

        if status != .ready {
            let locate = GlassPillButton(frame: NSRect(x: width - 110, y: 11, width: 69, height: 29),
                                          title: "Locate", symbol: "")
            locate.toolTip = "Choose the current location of this file or folder"
            locate.target = self
            locate.action = #selector(locateClicked)
            addSubview(locate)
        }

        let remove = GlassPillButton(frame: NSRect(x: width - 37, y: 12, width: 27, height: 27),
                                     title: "", symbol: "xmark")
        remove.toolTip = "Remove from shelf"
        remove.target = self
        remove.action = #selector(removeClicked)
        addSubview(remove)
        toolTip = status == .ready ? "Drag this file to Finder to move it" : detail
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func removeClicked() { removeAction(entry.id) }
    @objc private func locateClicked() { locateAction(entry.id) }
}

final class ShelfView: NSView {
    let store: ShelfStore
    var onHide: (() -> Void)?
    var onMove: (() -> Void)?
    var onAdd: (() -> Void)?
    var onGuide: (() -> Void)?
    var onLocate: ((UUID) -> Void)?
    var onQuit: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onEmptiedByMove: (() -> Void)?
    var onPositionChanged: ((NSPoint) -> Void)?
    private let contentWidth: CGFloat = 332
    private let backdrop = GlassBackdropView(frame: .zero)
    private let glassOverlay = GlassOverlayView(frame: .zero)
    private weak var dragAllButton: DragAllFilesView?
    private weak var dragHintLabel: NSTextField?
    private var hintResetTimer: Timer?
    private var moveFeedbackTimer: Timer?
    private var transientMovedCount: Int?
    private(set) var isDraggingFiles = false

    init(store: ShelfStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 174))
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = true
        backdrop.material = .popover
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 20
        backdrop.layer?.masksToBounds = true
        addSubview(backdrop)
        addSubview(glassOverlay)
        registerForDraggedTypes([.fileURL])
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glassOverlay.needsDisplay = true
    }

    func rebuild() {
        hintResetTimer?.invalidate()
        dragHintLabel = nil
        dragAllButton = nil
        for view in subviews where view !== backdrop && view !== glassOverlay {
            view.removeFromSuperview()
        }
        let entries = store.entries
        let readyEntries = entries.filter { store.status(for: $0) == .ready }
        let unavailableCount = entries.count - readyEntries.count
        let rowCount = min(entries.count, 6)
        let height: CGFloat = entries.isEmpty ? 174 : 149 + CGFloat(rowCount) * 55
        frame.size.height = height
        backdrop.frame = bounds
        glassOverlay.frame = bounds
        onResize?(height)

        let header = ShelfHeaderView(frame: NSRect(x: 0, y: height - 52, width: 360, height: 52))
        header.toolTip = "Drag here to move Fallet"
        header.onPositionChanged = { [weak self] point in self?.onPositionChanged?(point) }

        let logoWell = GlassDecorationView(frame: NSRect(x: 15, y: 10, width: 32, height: 32))
        logoWell.wantsLayer = true
        logoWell.layer?.cornerRadius = 11
        logoWell.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.13).cgColor
        logoWell.layer?.borderWidth = 1
        logoWell.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        let logo = NSImageView(frame: NSRect(x: 3, y: 3, width: 26, height: 26))
        if let iconURL = Bundle.main.url(forResource: "FalletIcon", withExtension: "png") {
            logo.image = NSImage(contentsOf: iconURL)
        }
        logo.imageScaling = .scaleProportionallyUpOrDown
        logoWell.addSubview(logo)
        header.addSubview(logoWell)

        let title = NSTextField(labelWithString: "Fallet")
        title.frame = NSRect(x: 57, y: 24, width: 127, height: 20)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = ShelfGlassStyle.primaryText
        header.addSubview(title)
        let summary = unavailableCount == 0
            ? "\(readyEntries.count) \(readyEntries.count == 1 ? "file" : "files") ready to move"
            : "\(readyEntries.count) ready · \(unavailableCount) unavailable"
        let subtitle = NSTextField(labelWithString: entries.isEmpty ? "Ready for files" : summary)
        subtitle.frame = NSRect(x: 57, y: 9, width: 127, height: 15)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = ShelfGlassStyle.secondaryText
        header.addSubview(subtitle)

        let guide = GlassPillButton(frame: NSRect(x: 190, y: 11, width: 48, height: 29), title: "Guide", symbol: "")
        guide.toolTip = "How to use Fallet"
        guide.target = self
        guide.action = #selector(guideClicked)
        header.addSubview(guide)
        addIconButton("plus", tip: "Add files", x: 246, action: #selector(addClicked), to: header)
        addIconButton("minus", tip: "Hide shelf", x: 282, action: #selector(hideClicked), to: header)
        addIconButton("power", tip: "Quit Fallet", x: 318, action: #selector(quitClicked), to: header)
        addSubview(header)

        if entries.isEmpty {
            addEmptyState()
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 14, y: 16, width: contentWidth, height: CGFloat(rowCount) * 55))
            scroll.hasVerticalScroller = entries.count > 6
            scroll.drawsBackground = false
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: CGFloat(entries.count) * 55))
            for (index, entry) in entries.enumerated() {
                let row = FileRowView(entry: entry, status: store.status(for: entry), width: contentWidth,
                                      removeAction: { [weak self] id in self?.store.remove([id]) },
                                      locateAction: { [weak self] id in self?.onLocate?(id) })
                row.frame.origin = NSPoint(x: 0, y: CGFloat(entries.count - index - 1) * 55 + 2)
                row.onMoved = { [weak self] urls in
                    self?.removeMovedFiles(urls, from: [entry])
                }
                row.onDragStarted = { [weak self] in self?.isDraggingFiles = true }
                row.onDragCancelled = { [weak self] in self?.isDraggingFiles = false }
                row.shouldRemoveMissingURL = { [weak self] _ in
                    self?.store.entries.first(where: { $0.id == entry.id }).map {
                        self?.store.status(for: $0) == .missing
                    } ?? false
                }
                document.addSubview(row)
            }
            scroll.documentView = document
            addSubview(scroll)

            if !readyEntries.isEmpty {
                let dragAll = DragAllFilesView(frame: NSRect(x: 14, y: height - 98, width: 150, height: 38))
                dragAll.urls = readyEntries.map(\.url)
                dragAll.onMoved = { [weak self] urls in
                    self?.removeMovedFiles(urls, from: readyEntries, showFeedback: true)
                }
                dragAll.shouldRemoveMissingURL = { [weak self] url in
                    self?.store.entries.first(where: { $0.path == url.path }).map {
                        self?.store.status(for: $0) == .missing
                    } ?? false
                }
                dragAll.onClick = { [weak self] in self?.showDragHint() }
                dragAll.onPressChanged = { [weak dragAll] pressed in dragAll?.setPressed(pressed) }
                dragAll.onDragStarted = { [weak self, weak dragAll] in
                    self?.isDraggingFiles = true
                    self?.hintResetTimer?.invalidate()
                    dragAll?.setState(.dragging, count: readyEntries.count)
                    self?.dragHintLabel?.stringValue = "Drop in a Finder folder to move available files"
                }
                dragAll.onDragCancelled = { [weak self] in
                    self?.isDraggingFiles = false
                    self?.showDragHint()
                }
                if let movedCount = transientMovedCount {
                    dragAll.setState(.success, count: movedCount, animated: false)
                } else {
                    dragAll.setState(.ready, count: readyEntries.count, animated: false)
                }
                dragAllButton = dragAll
                addSubview(dragAll)

                let move = GlassPillButton(frame: NSRect(x: 172, y: height - 98, width: 96, height: 38),
                                           title: "Move to", symbol: "folder")
                move.toolTip = "Choose a destination folder"
                move.target = self
                move.action = #selector(moveClicked)
                addSubview(move)
            } else {
                let notice = NSTextField(labelWithString: "No files ready to move")
                notice.frame = NSRect(x: 17, y: height - 88, width: 248, height: 18)
                notice.font = .systemFont(ofSize: 11, weight: .medium)
                notice.textColor = ShelfGlassStyle.secondaryText
                addSubview(notice)
            }
            let clear = GlassPillButton(frame: NSRect(x: 276, y: height - 98, width: 70, height: 38),
                                        title: "Clear", symbol: "xmark")
            clear.toolTip = "Remove all files from shelf without moving them"
            clear.target = self
            clear.action = #selector(clearClicked)
            addSubview(clear)

            let hint = NSTextField(labelWithString: transientMovedCount.map { "Moved \($0) files. Drag the rest when ready." }
                                         ?? (unavailableCount > 0 ? "Locate missing files or reconnect their drive"
                                             : "Hold Drag all and drop in a Finder folder"))
            hint.frame = NSRect(x: 17, y: height - 121, width: 326, height: 15)
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = ShelfGlassStyle.secondaryText
            dragHintLabel = hint
            addSubview(hint)
        }
    }

    private func addEmptyState() {
        let zone = GlassDecorationView(frame: NSRect(x: 14, y: 15, width: 332, height: 102))
        zone.wantsLayer = true
        zone.layer?.cornerRadius = 16
        zone.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.07).cgColor
        zone.layer?.borderWidth = 1
        zone.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.16).cgColor
        addSubview(zone)

        if let movedCount = transientMovedCount {
            let success = DragAllFilesView(frame: NSRect(x: 91, y: 57, width: 178, height: 38))
            success.setState(.success, count: movedCount, animated: false)
            addSubview(success)
            let caption = NSTextField(labelWithString: "All files moved")
            caption.frame = NSRect(x: 50, y: 34, width: 260, height: 16)
            caption.alignment = .center
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = ShelfGlassStyle.secondaryText
            addSubview(caption)
        } else {
            let icon = NSImageView(frame: NSRect(x: 165, y: 79, width: 30, height: 30))
            icon.image = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: "Drop files")
            icon.contentTintColor = ShelfGlassStyle.primaryText
            addSubview(icon)
            let prompt = NSTextField(labelWithString: "Drop files here")
            prompt.frame = NSRect(x: 50, y: 54, width: 260, height: 19)
            prompt.alignment = .center
            prompt.font = .systemFont(ofSize: 13, weight: .semibold)
            prompt.textColor = ShelfGlassStyle.primaryText
            addSubview(prompt)
            let instruction = NSTextField(labelWithString: "Or shake while dragging to summon the shelf")
            instruction.frame = NSRect(x: 26, y: 36, width: 308, height: 16)
            instruction.alignment = .center
            instruction.font = .systemFont(ofSize: 10)
            instruction.textColor = ShelfGlassStyle.secondaryText
            addSubview(instruction)
        }
    }

    private func addIconButton(_ symbol: String, tip: String, x: CGFloat, action: Selector, to parent: NSView) {
        let button = GlassPillButton(frame: NSRect(x: x, y: 11, width: 29, height: 29),
                                     title: "", symbol: symbol)
        button.toolTip = tip
        button.target = self
        button.action = action
        parent.addSubview(button)
    }

    @objc private func addClicked() { onAdd?() }
    @objc private func guideClicked() { onGuide?() }
    @objc private func hideClicked() { onHide?() }
    @objc private func moveClicked() { onMove?() }
    @objc private func clearClicked() { store.clear() }
    @objc private func quitClicked() { onQuit?() }

    private func showDragHint() {
        guard transientMovedCount == nil else { return }
        dragAllButton?.setState(.hint, count: store.entries.filter {
            store.status(for: $0) == .ready
        }.count)
        dragHintLabel?.stringValue = "Hold this button, then drag to a Finder folder"
        dragHintLabel?.textColor = ShelfGlassStyle.primaryText
        hintResetTimer?.invalidate()
        hintResetTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.dragAllButton?.setState(.ready, count: self.store.entries.filter {
                self.store.status(for: $0) == .ready
            }.count)
            self.dragHintLabel?.stringValue = self.store.entries.contains {
                self.store.status(for: $0) != .ready
            } ? "Locate missing files or reconnect their drive" : "Hold Drag all and drop in a Finder folder"
            self.dragHintLabel?.textColor = ShelfGlassStyle.secondaryText
        }
    }

    private func removeMovedFiles(_ urls: [URL], from sourceEntries: [ShelfEntry], showFeedback: Bool = false) {
        isDraggingFiles = false
        if showFeedback { transientMovedCount = urls.count }
        let movedPaths = Set(urls.map(\.path))
        store.remove(Set(sourceEntries.filter { movedPaths.contains($0.path) }.map(\.id)))
        guard showFeedback else {
            if store.entries.isEmpty { onEmptiedByMove?() }
            return
        }
        moveFeedbackTimer?.invalidate()
        moveFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.transientMovedCount = nil
            let shouldHide = self.store.entries.isEmpty
            self.rebuild()
            if shouldHide { self.onEmptiedByMove?() }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let acceptsFiles = sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        glassOverlay.isDropTarget = acceptsFiles
        return acceptsFiles ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { glassOverlay.isDropTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        glassOverlay.isDropTarget = false
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.map { $0 as URL }
        store.add(urls)
        return !urls.isEmpty
    }
}

#if !FALLET_CAPTURE
@main
final class FalletApp: NSObject, NSApplicationDelegate {
    private let store = ShelfStore()
    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private var shelfView: ShelfView!
    private var guideWindow: GuideWindow?
    private var activePicker: NSOpenPanel?
    private var shakeTimer: Timer?
    private var sourceRefreshTimer: Timer?
    private var shakeDetector = ShakeDetector()
    private var lastShakeReveal: TimeInterval = -100

    static func main() {
        let app = NSApplication.shared
        let delegate = FalletApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.makeStatusIcon()
        statusItem.button?.toolTip = "Show or hide Fallet"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleShelf)
        if let iconURL = Bundle.main.url(forResource: "Fallet", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        shelfView = ShelfView(store: store)
        panel = ShelfPanel(contentRect: shelfView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = shelfView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        shelfView.onResize = { [weak self] height in self?.resizePanel(to: height) }
        shelfView.onHide = { [weak self] in self?.panel.orderOut(nil) }
        shelfView.onEmptiedByMove = { [weak self] in self?.panel.orderOut(nil) }
        shelfView.onAdd = { [weak self] in self?.chooseFiles() }
        shelfView.onLocate = { [weak self] id in self?.locateSource(id) }
        shelfView.onGuide = { [weak self] in self?.showGuide() }
        shelfView.onMove = { [weak self] in self?.chooseDestination() }
        shelfView.onQuit = { NSApplication.shared.terminate(nil) }
        shelfView.onPositionChanged = { point in
            UserDefaults.standard.set([Double(point.x), Double(point.y)], forKey: "ShelfWindowTopLeft")
        }
        store.onChange = { [weak self] in self?.shelfView.rebuild() }
        restorePanelPosition()
        panel.orderFrontRegardless()
        startShakePolling()
        sourceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.shelfView.isDraggingFiles else { return }
            self.store.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeTimer?.invalidate()
        sourceRefreshTimer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        return true
    }

    @objc private func toggleShelf() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            store.refresh()
            panel.orderFrontRegardless()
        }
    }

    private func showGuide() {
        if guideWindow == nil { guideWindow = GuideWindow() }
        else if guideWindow?.isVisible == false { guideWindow?.resetGuide() }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    private func restorePanelPosition() {
        guard let screen = NSScreen.main else { return }
        let saved = (UserDefaults.standard.array(forKey: "ShelfWindowTopLeft") as? [Double])
            ?? (UserDefaults(suiteName: "dev.local.dropshelf")?.array(forKey: "ShelfWindowTopLeft") as? [Double])
        if let saved, saved.count == 2 {
            let topLeft = NSPoint(x: saved[0], y: saved[1])
            let targetScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(topLeft) }) ?? screen
            let visible = targetScreen.visibleFrame
            let x = min(max(topLeft.x, visible.minX), visible.maxX - panel.frame.width)
            let y = min(max(topLeft.y - panel.frame.height, visible.minY), visible.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 18,
                                         y: visible.maxY - panel.frame.height - 12))
        }
    }

    private func startShakePolling() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.checkForShake()
        }
        RunLoop.main.add(timer, forMode: .common)
        shakeTimer = timer
    }

    private func checkForShake() {
        let finderIsActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        let leftButtonHeld = NSEvent.pressedMouseButtons & 1 != 0
            || CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard finderIsActive && leftButtonHeld else {
            shakeDetector.reset()
            return
        }
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastShakeReveal > 2 else { return }
        let pointer = NSEvent.mouseLocation
        guard shakeDetector.sample(x: pointer.x, y: pointer.y, at: time) else { return }
        lastShakeReveal = time
        showShelf(near: pointer)
    }

    private func showShelf(near pointer: NSPoint) {
        store.refresh()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let preferredX = pointer.x + 28 + size.width <= visible.maxX
            ? pointer.x + 28 : pointer.x - size.width - 28
        let preferredY = pointer.y - size.height - 18 >= visible.minY
            ? pointer.y - size.height - 18 : pointer.y + 28
        let x = min(max(preferredX, visible.minX), visible.maxX - size.width)
        let y = min(max(preferredY, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
    }

    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func chooseFiles() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.prompt = "Add to Shelf"
        presentPicker(picker) { [weak self] result in
            if result == .OK { self?.store.add(picker.urls) }
        }
    }

    private func chooseDestination() {
        store.refresh()
        let readyEntries = store.entries.filter { store.status(for: $0) == .ready }
        guard !readyEntries.isEmpty else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.canCreateDirectories = true
        picker.prompt = "Move Files Here"
        presentPicker(picker) { [weak self] result in
            guard result == .OK, let directory = picker.url, let self else { return }
            self.store.refresh()
            let currentReady = self.store.entries.filter { self.store.status(for: $0) == .ready }
            let result = FileMover.move(currentReady.map(\.url), to: directory)
            self.store.removePaths(Set(result.moved.map(\.path)))
            if self.store.entries.isEmpty { self.panel.orderOut(nil) }
            if !result.errors.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Some files could not be moved"
                alert.informativeText = result.errors.joined(separator: "\n")
                alert.runModal()
            }
        }
    }

    private func locateSource(_ id: UUID) {
        guard let entry = store.entries.first(where: { $0.id == id }) else { return }
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = false
        picker.prompt = "Relink"
        picker.message = "Choose the current location of \(entry.url.lastPathComponent)."
        let parent = entry.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.path) { picker.directoryURL = parent }
        presentPicker(picker) { [weak self] result in
            guard result == .OK, let url = picker.url, let self else { return }
            if !self.store.relink(id, to: url) {
                let alert = NSAlert()
                alert.messageText = "Could not relink this item"
                alert.informativeText = "Choose an existing file or folder that is not already on the shelf."
                alert.runModal()
            }
        }
    }

    private func presentPicker(_ picker: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let activePicker {
            NSApp.activate(ignoringOtherApps: true)
            activePicker.orderFrontRegardless()
            return
        }

        activePicker = picker
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            self?.activePicker = nil
            completion(response)
        }
        picker.level = .modalPanel
        picker.makeKeyAndOrderFront(nil)
    }

    private static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for row in 0..<4 {
                for column in 0..<4 {
                    let tile = NSRect(x: 0.9 + CGFloat(column) * 4.1,
                                      y: 0.9 + CGFloat(row) * 4.1,
                                      width: 3.25, height: 3.25)
                    NSBezierPath(roundedRect: tile, xRadius: 0.75, yRadius: 0.75).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
