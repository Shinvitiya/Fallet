import AppKit
import Carbon
import ImageIO
import QuickLookUI
import UniformTypeIdentifiers
import Vision

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

class StatusDropView: NSView {
    var onClick: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var onRightClick: ((NSEvent, NSView) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event, self) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        return types.contains { [.fileURL, .URL, .string, .png, .tiff].contains($0) } ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}

final class NotchDropView: StatusDropView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = NSColor(calibratedWhite: 0.19, alpha: 0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        let icon = NSImageView(frame: NSRect(x: 14, y: 12, width: 17, height: 17))
        icon.image = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Drop on Fallet")
        icon.contentTintColor = .white
        addSubview(icon)
        let label = NSTextField(labelWithString: "Drop on Fallet")
        label.frame = NSRect(x: 38, y: 11, width: 102, height: 17)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
    var promisedImagePaths: Set<String> = []
    var contentWriter: NSPasteboardWriting?
    var onMoved: (([URL]) -> Void)?
    var onPromisedImageWritten: ((URL) -> Void)?
    var onClick: (() -> Void)?
    var onPressChanged: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragCancelled: (() -> Void)?
    var shouldRemoveMissingURL: ((URL) -> Bool)?
    var showsPressFeedback = false
    private var pendingURLs: [URL] = []
    private var pendingPromiseIDs: [UUID] = []
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
        guard (!urls.isEmpty || contentWriter != nil), !dragStarted, let mouseDownEvent else { return }
        let start = mouseDownEvent.locationInWindow
        let current = event.locationInWindow
        guard hypot(current.x - start.x, current.y - start.y) >= 3 else { return }
        dragStarted = true
        onDragStarted?()
        pendingURLs = urls.filter { !promisedImagePaths.contains($0.standardizedFileURL.path) }
        pendingPromiseIDs = []
        var items = urls.enumerated().map { index, url -> NSDraggingItem in
            let writer: NSPasteboardWriting
            if promisedImagePaths.contains(url.standardizedFileURL.path) {
                let callback = onPromisedImageWritten
                let promise = ShelfImageFilePromise(sourceURL: url) { writtenURL in callback?(writtenURL) }
                pendingPromiseIDs.append(promise.id)
                writer = promise.makeProvider()
            } else {
                writer = url as NSURL
            }
            let item = NSDraggingItem(pasteboardWriter: writer)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let origin = NSPoint(x: 14 + CGFloat(index % 4) * 5, y: bounds.midY - 16 - CGFloat(index % 4) * 5)
            item.setDraggingFrame(NSRect(origin: origin, size: icon.size), contents: icon)
            return item
        }
        if let contentWriter {
            let item = NSDraggingItem(pasteboardWriter: contentWriter)
            let image = NSImage(systemSymbolName: contentWriter is NSURL ? "link" : "text.alignleft",
                                accessibilityDescription: "Shelf content") ?? NSImage(size: NSSize(width: 32, height: 32))
            item.setDraggingFrame(NSRect(x: 14, y: bounds.midY - 16, width: 32, height: 32), contents: image)
            items.append(item)
        }
        beginDraggingSession(with: items, event: mouseDownEvent, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if !urls.isEmpty && pendingURLs.isEmpty { return .copy }
        return urls.isEmpty ? .copy : [.move, .copy]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation.isEmpty { ShelfImageFilePromise.cancel(pendingPromiseIDs) }
        pendingPromiseIDs = []
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
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    private let entry: ShelfEntry
    private let removeAction: (UUID) -> Void
    private var isRemoving = false
    private let locateAction: (UUID) -> Void
    var onPreview: (() -> Void)?
    var onRename: (() -> Void)?
    var onShare: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onActions: (() -> Void)?

    init(entry: ShelfEntry, status: ShelfEntryStatus, width: CGFloat,
         removeAction: @escaping (UUID) -> Void, locateAction: @escaping (UUID) -> Void) {
        self.entry = entry
        self.removeAction = removeAction
        self.locateAction = locateAction
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 51))
        if status == .ready {
            if entry.isFileLike {
                urls = [entry.url]
                if entry.kind == .image { promisedImagePaths = [entry.url.standardizedFileURL.path] }
            }
            else if entry.kind == .link, let url = URL(string: entry.content ?? "") { contentWriter = url as NSURL }
            else if entry.kind == .text { contentWriter = (entry.content ?? "") as NSString }
        }
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = (status == .ready ? ShelfGlassStyle.rowBorder
                              : NSColor.systemOrange.withAlphaComponent(0.55)).cgColor
        layer?.backgroundColor = ShelfGlassStyle.rowFill.cgColor

        let thumbnail = status == .ready && entry.kind == .image ? Self.thumbnail(at: entry.url) : nil
        let iconWell = NSView(frame: thumbnail == nil
            ? NSRect(x: 9, y: 7, width: 37, height: 37)
            : NSRect(x: 7, y: 4, width: 43, height: 43))
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 10
        iconWell.layer?.masksToBounds = true
        iconWell.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.11).cgColor
        addSubview(iconWell)

        let icon = NSImageView(frame: thumbnail == nil
            ? NSRect(x: 5, y: 5, width: 27, height: 27) : iconWell.bounds)
        switch status {
        case .ready:
            switch entry.kind {
            case .file, .archive: icon.image = NSWorkspace.shared.icon(forFile: entry.path)
            case .image: icon.image = thumbnail ?? NSWorkspace.shared.icon(forFile: entry.path)
            case .link: icon.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Link")
            case .text: icon.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Text")
            }
        case .missing: icon.image = NSImage(systemSymbolName: "questionmark.folder.fill", accessibilityDescription: "Missing source")
        case .volumeUnavailable: icon.image = NSImage(systemSymbolName: "externaldrive.badge.xmark", accessibilityDescription: "Drive disconnected")
        }
        if status != .ready { icon.contentTintColor = .systemOrange }
        icon.imageScaling = .scaleProportionallyUpOrDown
        iconWell.addSubview(icon)

        let name = NSTextField(labelWithString: entry.title)
        name.frame = NSRect(x: 56, y: 26, width: width - (status == .ready ? 100 : 171), height: 17)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = ShelfGlassStyle.primaryText
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)

        let detail: String
        switch status {
        case .ready:
            switch entry.kind {
            case .file: detail = entry.url.deletingLastPathComponent().lastPathComponent
            case .image: detail = "Image · drag to save"
            case .archive: detail = "Temporary ZIP · drag to keep"
            case .link: detail = entry.content ?? "Link"
            case .text: detail = "Text snippet · drag to paste"
            }
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
        remove.toolTip = entry.kind == .archive ? "Permanently delete this temporary ZIP"
            : entry.kind == .image ? "Remove saved image from shelf" : "Remove from shelf"
        remove.target = self
        remove.action = #selector(removeClicked)
        addSubview(remove)
        toolTip = status == .ready && entry.kind == .archive
            ? "Drag to Finder or use Move to. Clear or Quit permanently deletes this ZIP."
            : status == .ready ? "Drag to another app, or right-click for more options" : detail
        let context = NSMenu()
        let preview = context.addItem(withTitle: "Preview", action: #selector(previewClicked), keyEquivalent: "")
        preview.target = self
        if entry.isFileLike {
            let rename = context.addItem(withTitle: "Rename…", action: #selector(renameClicked), keyEquivalent: "")
            rename.target = self
        }
        context.addItem(.separator())
        let up = context.addItem(withTitle: "Move Up", action: #selector(moveUpClicked), keyEquivalent: "")
        up.target = self
        let down = context.addItem(withTitle: "Move Down", action: #selector(moveDownClicked), keyEquivalent: "")
        down.target = self
        context.addItem(.separator())
        let share = context.addItem(withTitle: "Share…", action: #selector(shareClicked), keyEquivalent: "")
        share.target = self
        let actions = context.addItem(withTitle: "More Actions…", action: #selector(actionsClicked), keyEquivalent: "")
        actions.target = self
        menu = context
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func thumbnail(at url: URL) -> NSImage? {
        let key = url.standardizedFileURL.path as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
              ] as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnailCache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    @objc private func removeClicked() {
        guard !isRemoving else { return }
        isRemoving = true
        guard !ShelfGlassStyle.reduceMotion else {
            removeAction(entry.id)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.animator().alphaValue = 0
        } completionHandler: {
            self.removeAction(self.entry.id)
        }
    }
    @objc private func locateClicked() { locateAction(entry.id) }
    @objc private func previewClicked() { onPreview?() }
    @objc private func renameClicked() { onRename?() }
    @objc private func shareClicked() { onShare?() }
    @objc private func moveUpClicked() { onMoveUp?() }
    @objc private func moveDownClicked() { onMoveDown?() }
    @objc private func actionsClicked() { onActions?() }
}

final class ShelfView: NSView {
    let store: ShelfStore
    var onHide: (() -> Void)?
    var onMove: (() -> Void)?
    var onLocate: ((UUID) -> Void)?
    var onPreview: ((ShelfEntry) -> Void)?
    var onRename: ((ShelfEntry) -> Void)?
    var onShare: ((ShelfEntry, NSView) -> Void)?
    var onTools: ((ShelfEntry?, NSView) -> Void)?
    var onResize: ((CGFloat) -> Void)?
    var onEmptiedByMove: (() -> Void)?
    var onPositionChanged: ((NSPoint) -> Void)?
    private let contentWidth: CGFloat = 332
    private let backdrop = GlassBackdropView(frame: .zero)
    private let glassOverlay = GlassOverlayView(frame: .zero)
    private weak var dragAllButton: DragAllFilesView?
    private weak var dragHintLabel: NSTextField?
    private weak var itemScrollView: NSScrollView?
    private var entryRows: [UUID: FileRowView] = [:]
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
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glassOverlay.needsDisplay = true
    }

    func rebuild() {
        let previousScrollY = itemScrollView?.contentView.bounds.minY
        let previousMaxY = itemScrollView.flatMap { scroll -> CGFloat? in
            guard let document = scroll.documentView else { return nil }
            return max(0, document.frame.height - scroll.contentView.bounds.height)
        }
        hintResetTimer?.invalidate()
        dragHintLabel = nil
        dragAllButton = nil
        itemScrollView = nil
        entryRows.removeAll()
        for view in subviews where view !== backdrop && view !== glassOverlay {
            view.removeFromSuperview()
        }
        let entries = store.entries
        let readyEntries = entries.filter { $0.isFileLike && store.status(for: $0) == .ready }
        let unavailableCount = entries.filter { $0.isFileLike && store.status(for: $0) != .ready }.count
        let fileEntries = entries.filter(\.isFileLike)
        let contentEntries = entries.filter { !$0.isFileLike }
        let hasFileSection = !fileEntries.isEmpty
        let sectionGap: CGFloat = hasFileSection && !contentEntries.isEmpty ? 12 : 0
        let contentHeadingHeight: CGFloat = contentEntries.isEmpty ? 0 : 26
        let documentHeight = CGFloat(entries.count) * 55 + contentHeadingHeight + sectionGap
        let scrollHeight = min(documentHeight, CGFloat(min(entries.count, 6)) * 55
            + contentHeadingHeight + sectionGap)
        let height: CGFloat = entries.isEmpty ? 174 : (hasFileSection ? 174 : 78) + scrollHeight
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
        title.frame = NSRect(x: 57, y: 24, width: 100, height: 20)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = ShelfGlassStyle.primaryText
        header.addSubview(title)
        let summary = unavailableCount == 0
            ? "\(entries.count) \(entries.count == 1 ? "item" : "items") on shelf"
            : "\(readyEntries.count) ready · \(unavailableCount) unavailable"
        let subtitle = NSTextField(labelWithString: entries.isEmpty ? "Ready for files" : summary)
        subtitle.frame = NSRect(x: 57, y: 9, width: 105, height: 15)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = ShelfGlassStyle.secondaryText
        header.addSubview(subtitle)

        let tools = GlassPillButton(frame: NSRect(x: 282, y: 11, width: 29, height: 29),
                                    title: "", symbol: "ellipsis")
        tools.toolTip = "More actions"
        tools.target = self
        tools.action = #selector(toolsClicked(_:))
        header.addSubview(tools)
        addIconButton("minus", tip: "Hide shelf", x: 318, action: #selector(hideClicked), to: header)
        addSubview(header)

        if entries.isEmpty {
            addEmptyState()
        } else {
            let scroll = NSScrollView(frame: NSRect(x: 14, y: 16, width: contentWidth, height: scrollHeight))
            scroll.hasVerticalScroller = documentHeight > scrollHeight
            scroll.drawsBackground = false
            scroll.scrollerStyle = .overlay
            let document = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: documentHeight))
            var cursorY = documentHeight
            for (name, sectionEntries) in [("FILES & FOLDERS", fileEntries),
                                           ("TEXT & LINKS", contentEntries)] where !sectionEntries.isEmpty {
                if name == "TEXT & LINKS" {
                    cursorY -= sectionGap
                    let label = NSTextField(labelWithString: "\(name)  ·  \(sectionEntries.count)")
                    label.frame = NSRect(x: 6, y: cursorY - 20, width: 220, height: 15)
                    label.font = .systemFont(ofSize: 9, weight: .bold)
                    label.textColor = ShelfGlassStyle.secondaryText
                    document.addSubview(label)
                    cursorY -= 26
                }
                for entry in sectionEntries {
                    let row = FileRowView(entry: entry, status: store.status(for: entry), width: contentWidth,
                                          removeAction: { [weak self] id in self?.store.remove([id]) },
                                          locateAction: { [weak self] id in self?.onLocate?(id) })
                    row.frame.origin = NSPoint(x: 0, y: cursorY - 55 + 2)
                    row.onMoved = { [weak self] urls in
                        self?.removeMovedFiles(urls, from: [entry])
                    }
                    row.onPromisedImageWritten = { [weak self] url in
                        self?.removeMovedFiles([url], from: [entry])
                    }
                    row.onClick = { [weak self] in self?.onPreview?(entry) }
                    row.onPreview = { [weak self] in self?.onPreview?(entry) }
                    row.onRename = { [weak self] in self?.onRename?(entry) }
                    row.onShare = { [weak self, weak row] in
                        guard let row else { return }
                        self?.onShare?(entry, row)
                    }
                    row.onMoveUp = { [weak self] in self?.store.moveEntry(entry.id, by: -1) }
                    row.onMoveDown = { [weak self] in self?.store.moveEntry(entry.id, by: 1) }
                    row.onActions = { [weak self, weak row] in
                        guard let row else { return }
                        self?.onTools?(entry, row)
                    }
                    row.onDragStarted = { [weak self] in self?.isDraggingFiles = true }
                    row.onDragCancelled = { [weak self] in self?.isDraggingFiles = false }
                    row.shouldRemoveMissingURL = { [weak self] _ in
                        self?.store.entries.first(where: { $0.id == entry.id }).map {
                            self?.store.status(for: $0) == .missing
                        } ?? false
                    }
                    document.addSubview(row)
                    entryRows[entry.id] = row
                    cursorY -= 55
                }
            }
            scroll.documentView = document
            let maxY = max(0, documentHeight - scrollHeight)
            let initialY: CGFloat
            if let previousScrollY, let previousMaxY {
                initialY = previousScrollY < 2 ? 0
                    : min(maxY, max(0, maxY - (previousMaxY - previousScrollY)))
            } else {
                initialY = maxY
            }
            scroll.contentView.scroll(to: NSPoint(x: 0, y: initialY))
            scroll.reflectScrolledClipView(scroll.contentView)
            addSubview(scroll)
            itemScrollView = scroll

            if hasFileSection {
                let fileHeading = NSTextField(labelWithString: "FILES & FOLDERS  ·  \(fileEntries.count)")
                fileHeading.frame = NSRect(x: 20, y: height - 77, width: 220, height: 15)
                fileHeading.font = .systemFont(ofSize: 9, weight: .bold)
                fileHeading.textColor = ShelfGlassStyle.secondaryText
                addSubview(fileHeading)
            }

            if !readyEntries.isEmpty {
                let dragAll = DragAllFilesView(frame: NSRect(x: 14, y: height - 124, width: 150, height: 38))
                dragAll.urls = readyEntries.map(\.url)
                dragAll.promisedImagePaths = Set(readyEntries.filter { $0.kind == .image }
                    .map { $0.url.standardizedFileURL.path })
                dragAll.onMoved = { [weak self] urls in
                    self?.removeMovedFiles(urls, from: readyEntries, showFeedback: true)
                }
                dragAll.onPromisedImageWritten = { [weak self] url in
                    self?.removeMovedFiles([url], from: readyEntries, showFeedback: true)
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

                let move = GlassPillButton(frame: NSRect(x: 172, y: height - 124, width: 96, height: 38),
                                           title: "Move to", symbol: "folder")
                move.toolTip = "Choose a destination folder"
                move.target = self
                move.action = #selector(moveClicked)
                addSubview(move)
            } else if hasFileSection {
                let notice = NSTextField(labelWithString: "No files ready to move")
                notice.frame = NSRect(x: 17, y: height - 113, width: 248, height: 18)
                notice.font = .systemFont(ofSize: 11, weight: .medium)
                notice.textColor = ShelfGlassStyle.secondaryText
                addSubview(notice)
            }
            let clear = GlassPillButton(frame: hasFileSection
                                            ? NSRect(x: 276, y: height - 124, width: 70, height: 38)
                                            : NSRect(x: 205, y: 7, width: 70, height: 38),
                                        title: "Clear", symbol: "xmark")
            clear.toolTip = "Clear shelf; original files stay, saved images and temporary ZIPs are deleted"
            clear.target = self
            clear.action = #selector(clearClicked)
            if hasFileSection { addSubview(clear) } else { header.addSubview(clear) }

            if hasFileSection {
                let hint = NSTextField(labelWithString: transientMovedCount.map { "Moved \($0) files. Drag the rest when ready." }
                                             ?? (unavailableCount > 0 ? "Locate missing files or reconnect their drive"
                                                 : "Hold Drag all and drop in a Finder folder"))
                hint.frame = NSRect(x: 17, y: height - 146, width: 326, height: 15)
                hint.font = .systemFont(ofSize: 10)
                hint.textColor = ShelfGlassStyle.secondaryText
                dragHintLabel = hint
                addSubview(hint)
            }
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
            let prompt = NSTextField(labelWithString: "Drop files, links, images or text")
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

    @objc private func toolsClicked(_ sender: NSView) { onTools?(nil, sender) }
    @objc private func hideClicked() { onHide?() }
    @objc private func moveClicked() { onMove?() }
    @objc private func clearClicked() { store.clear() }

    private func showDragHint() {
        guard transientMovedCount == nil else { return }
        dragAllButton?.setState(.hint, count: store.entries.filter {
            $0.isFileLike && store.status(for: $0) == .ready
        }.count)
        dragHintLabel?.stringValue = "Hold this button, then drag to a Finder folder"
        dragHintLabel?.textColor = ShelfGlassStyle.primaryText
        hintResetTimer?.invalidate()
        hintResetTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.dragAllButton?.setState(.ready, count: self.store.entries.filter {
                $0.isFileLike && self.store.status(for: $0) == .ready
            }.count)
            self.dragHintLabel?.stringValue = self.store.entries.contains {
                $0.isFileLike && self.store.status(for: $0) != .ready
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
        let types = sender.draggingPasteboard.types ?? []
        let accepts = types.contains { [.fileURL, .URL, .string, .png, .tiff].contains($0) }
        glassOverlay.isDropTarget = accepts
        return accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { glassOverlay.isDropTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        glassOverlay.isDropTarget = false
        return addFromPasteboard(sender.draggingPasteboard)
    }

    @discardableResult
    func addFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let previousIDs = Set(store.entries.map(\.id))
        defer {
            if let newEntry = store.entries.last(where: { !previousIDs.contains($0.id) }) {
                scrollToEntry(newEntry.id)
                DispatchQueue.main.async { [weak self] in self?.scrollToEntry(newEntry.id) }
            }
        }
        let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        if !files.isEmpty {
            store.add(files.map { $0 as URL })
            return true
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return store.addImage(png)
        }
        if let urlString = pasteboard.string(forType: .URL), let url = URL(string: urlString),
           !url.isFileURL {
            store.addLink(url)
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
               ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                store.addLink(url)
            } else {
                store.addText(string)
            }
            return true
        }
        return false
    }

    func scrollToEntry(_ id: UUID) {
        guard let scroll = itemScrollView, let row = entryRows[id],
              let document = scroll.documentView else { return }
        let visible = scroll.contentView.bounds
        guard !visible.contains(row.frame) else { return }
        let targetY = row.frame.maxY > visible.maxY
            ? row.frame.maxY - visible.height + 8 : row.frame.minY - 8
        let maxY = max(0, document.frame.height - visible.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

#if !FALLET_CAPTURE
@main
final class FalletApp: NSObject, NSApplicationDelegate {
    private let store = ShelfStore()
    private var statusItem: NSStatusItem!
    private var statusDropView: StatusDropView?
    private var notchPanel: NSPanel?
    private var panel: ShelfPanel!
    private var shelfView: ShelfView!
    private var guideWindow: GuideWindow?
    private var activePicker: NSOpenPanel?
    private let actionPopover = ShelfActionPopover()
    private var previewWindow: NSWindow?
    private var sharingPicker: NSSharingServicePicker?
    private var contentEntryWindow: ContentEntryWindow?
    private var shakeTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
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
        statusItem.button?.toolTip = "Click to show or hide Fallet; right-click for Quit"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleShelf)
        if let iconURL = Bundle.main.url(forResource: "Fallet", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        shelfView = ShelfView(store: store)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if let button = statusItem.button {
            let dropView = StatusDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onClick = { [weak self] in self?.toggleShelf() }
            dropView.onRightClick = { [weak self] event, view in
                self?.showStatusMenu(for: event, in: view)
            }
            dropView.onDrop = { [weak self] pasteboard in
                guard let self else { return false }
                let added = self.shelfView.addFromPasteboard(pasteboard)
                if added { self.panel.orderFrontRegardless() }
                return added
            }
            button.addSubview(dropView)
            statusDropView = dropView
        }
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
        shelfView.onLocate = { [weak self] id in self?.locateSource(id) }
        shelfView.onPreview = { [weak self] entry in self?.preview(entry) }
        shelfView.onRename = { [weak self] entry in self?.rename(entry) }
        shelfView.onShare = { [weak self] entry, anchor in self?.share([entry], from: anchor) }
        shelfView.onTools = { [weak self] entry, anchor in self?.showTools(for: entry, from: anchor) }
        shelfView.onMove = { [weak self] in self?.chooseDestination() }
        shelfView.onPositionChanged = { point in
            UserDefaults.standard.set([Double(point.x), Double(point.y)], forKey: "ShelfWindowTopLeft")
        }
        store.onChange = { [weak self] in self?.shelfView.rebuild() }
        restorePanelPosition()
        panel.orderFrontRegardless()
        configureNotchTarget()
        installHotKey()
        startShakePolling()
        sourceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.shelfView.isDraggingFiles else { return }
            self.store.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeTimer?.invalidate()
        sourceRefreshTimer?.invalidate()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        store.removeTemporaryArchives()
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

    private func showStatusMenu(for event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: panel.isVisible ? "Hide Fallet" : "Show Fallet",
                                action: #selector(toggleShelf), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Fallet", action: #selector(quitFallet), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func quitFallet() { NSApp.terminate(nil) }

    @objc(addToShelf:userData:error:)
    func addToShelf(_ pasteboard: NSPasteboard, userData: String?,
                    error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        if shelfView.addFromPasteboard(pasteboard) { panel.orderFrontRegardless() }
        else { error?.pointee = "Fallet could not read the selected item." }
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

    private func installHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, context in
            guard let context else { return noErr }
            let app = Unmanaged<FalletApp>.fromOpaque(context).takeUnretainedValue()
            app.toggleShelf()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let identifier = EventHotKeyID(signature: OSType(0x46414C54), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func checkForShake() {
        let finderIsActive = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        let leftButtonHeld = NSEvent.pressedMouseButtons & 1 != 0
            || CGEventSource.buttonState(.combinedSessionState, button: .left)
        updateNotchTarget(leftButtonHeld: leftButtonHeld, pointer: NSEvent.mouseLocation)
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

    private func configureNotchTarget() {
        guard NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }) else { return }
        let frame = NSRect(x: 0, y: 0, width: 154, height: 42)
        let target = NotchDropView(frame: frame)
        target.onDrop = { [weak self] pasteboard in
            guard let self else { return false }
            let added = self.shelfView.addFromPasteboard(pasteboard)
            self.notchPanel?.orderOut(nil)
            if added { self.panel.orderFrontRegardless() }
            return added
        }
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.contentView = target
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.orderOut(nil)
        notchPanel = window
    }

    private func updateNotchTarget(leftButtonHeld: Bool, pointer: NSPoint) {
        guard let notchPanel,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              screen.safeAreaInsets.top > 0,
              leftButtonHeld,
              abs(pointer.x - screen.frame.midX) < 105,
              pointer.y > screen.visibleFrame.maxY - 46 else {
            if notchPanel?.isVisible == true { notchPanel?.orderOut(nil) }
            return
        }
        let x = screen.frame.midX - notchPanel.frame.width / 2
        let y = screen.visibleFrame.maxY - notchPanel.frame.height - 4
        notchPanel.setFrameOrigin(NSPoint(x: x, y: y))
        if !notchPanel.isVisible { notchPanel.orderFrontRegardless() }
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
        let readyEntries = store.entries.filter { $0.isFileLike && store.status(for: $0) == .ready }
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
            let currentReady = self.store.entries.filter { $0.isFileLike && self.store.status(for: $0) == .ready }
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

private extension FalletApp {
    func showTools(for entry: ShelfEntry?, from anchor: NSView) {
        let target = entry.flatMap { item in store.entries.first(where: { $0.id == item.id }) }
        let files = (target.map { [$0] } ?? store.entries).filter {
            $0.isFileLike && store.status(for: $0) == .ready
        }
        let image = target.flatMap { item in
            item.isFileLike && store.status(for: item) == .ready && isImageFile(item.url) ? item : nil
        }
        let collect: [ShelfActionOption] = target == nil ? [
            ShelfActionOption("Paste from Clipboard", detail: "Add copied files, links, images or text", symbol: "doc.on.clipboard") { [weak self] in
                guard let self else { return }
                if self.shelfView.addFromPasteboard(.general) { self.panel.orderFrontRegardless() }
            },
            ShelfActionOption("Add Files…", detail: "Choose files or folders", symbol: "plus") { [weak self] in self?.chooseFiles() },
            ShelfActionOption("Add Text…", detail: "Write a note for the shelf", symbol: "text.alignleft") { [weak self] in self?.addTypedContent(as: .text) },
            ShelfActionOption("Add Link…", detail: "Save a web address", symbol: "link") { [weak self] in self?.addTypedContent(as: .link) },
            ShelfActionOption("Copy Shelf", detail: "Copy available items to the clipboard", symbol: "doc.on.doc") { [weak self] in
                self?.copyItems(self?.store.entries ?? [])
            },
            ShelfActionOption("How to Use", detail: "Explore Fallet’s features", symbol: "questionmark.circle") { [weak self] in
                self?.showGuide()
            }
        ] : [
            ShelfActionOption("Preview", detail: "Open a larger view of this item", symbol: "eye") { [weak self] in
                guard let target else { return }; self?.preview(target)
            },
            ShelfActionOption("Rename…", detail: "Rename the source file", symbol: "pencil", enabled: target?.isFileLike == true) { [weak self] in
                guard let target else { return }; self?.rename(target)
            },
            ShelfActionOption("Move Up", detail: "Place earlier on the shelf", symbol: "arrow.up") { [weak self] in
                guard let target else { return }; self?.store.moveEntry(target.id, by: -1)
            },
            ShelfActionOption("Move Down", detail: "Place later on the shelf", symbol: "arrow.down") { [weak self] in
                guard let target else { return }; self?.store.moveEntry(target.id, by: 1)
            },
            ShelfActionOption("Copy", detail: "Copy this item to the clipboard", symbol: "doc.on.doc") { [weak self] in
                guard let target else { return }; self?.copyItems([target])
            },
            ShelfActionOption("How to Use", detail: "Explore Fallet’s features", symbol: "questionmark.circle") { [weak self] in
                self?.showGuide()
            }
        ]
        var actions: [ShelfActionOption] = [
            ShelfActionOption("Share…", detail: "AirDrop, Mail, Messages and more", symbol: "square.and.arrow.up",
                              enabled: !(target.map { [$0] } ?? store.entries).isEmpty) { [weak self, weak anchor] in
                guard let self, let anchor else { return }
                self.share(target.map { [$0] } ?? self.store.entries, from: anchor)
            },
            ShelfActionOption("Create ZIP", detail: "Add a temporary ZIP to the shelf", symbol: "doc.zipper", enabled: !files.isEmpty) { [weak self] in
                self?.createZIP(from: files)
            }
        ]
        if let image {
            actions.append(ShelfActionOption("Resize Image…", detail: "Export a smaller image copy",
                                             symbol: "arrow.up.left.and.arrow.down.right") { [weak self] in
                self?.resizeImage(image)
            })
            actions.append(ShelfActionOption("Extract Text", detail: "Read text from an image",
                                             symbol: "text.viewfinder") { [weak self] in
                self?.extractText(from: image)
            })
        }
        actionPopover.show(from: anchor, titles: (target == nil ? "Collect" : "Item", "Actions"),
                           groups: (collect, actions))
    }

    func addTypedContent(as kind: ShelfEntryKind) {
        contentEntryWindow?.close()
        let window = ContentEntryWindow(kind: kind) { [weak self] value in
            guard let self else { return "Could not add this item." }
            guard !value.isEmpty else { return kind == .link ? "Enter a web address." : "Enter some text." }
            if kind == .text {
                self.store.addText(value)
                return nil
            }
            let address = value.contains("://") || value.lowercased().hasPrefix("mailto:")
                ? value : "https://" + value
            guard let url = URL(string: address),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "mailto" && !url.path.isEmpty
                    || ["http", "https"].contains(scheme) && url.host != nil) else {
                return "Enter a valid web address or email link."
            }
            self.store.addLink(url)
            return nil
        }
        contentEntryWindow = window
        window.present(above: panel)
    }

    func copyItems(_ entries: [ShelfEntry]) {
        let available = entries.filter { store.status(for: $0) == .ready }
        let board = NSPasteboard.general
        board.clearContents()
        let writers: [NSPasteboardWriting] = available.compactMap { entry in
            switch entry.kind {
            case .file, .image, .archive: return entry.url as NSURL
            case .link: return URL(string: entry.content ?? "") as NSURL?
            case .text: return (entry.content ?? "") as NSString
            }
        }
        if !writers.isEmpty { board.writeObjects(writers) }
    }

    func preview(_ entry: ShelfEntry) {
        guard store.status(for: entry) == .ready else { return }
        previewWindow?.close()
        let frame = NSRect(x: 0, y: 0, width: 680, height: 500)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = entry.title
        window.center()
        if entry.isFileLike {
            let preview = QLPreviewView(frame: frame)
            preview?.autoresizingMask = [.width, .height]
            preview?.previewItem = entry.url as NSURL
            window.contentView = preview
        } else {
            let scroll = NSScrollView(frame: frame)
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            let text = NSTextView(frame: frame.insetBy(dx: 20, dy: 20))
            text.isEditable = false
            text.isSelectable = true
            text.font = .systemFont(ofSize: 15)
            text.string = entry.content ?? ""
            scroll.documentView = text
            window.contentView = scroll
        }
        previewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func rename(_ entry: ShelfEntry) {
        guard entry.isFileLike, store.status(for: entry) == .ready else { return }
        let alert = NSAlert()
        alert.messageText = "Rename file"
        alert.informativeText = "This changes the file’s name in Finder too."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 25))
        field.stringValue = entry.url.lastPathComponent
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.renameFile(entry.id, to: field.stringValue) }
        catch { showError("Could not rename the file", error.localizedDescription) }
    }

    func share(_ entries: [ShelfEntry], from anchor: NSView) {
        let items: [Any] = entries.filter { store.status(for: $0) == .ready }.compactMap { entry in
            switch entry.kind {
            case .file, .image, .archive: return entry.url as NSURL
            case .link: return URL(string: entry.content ?? "") as NSURL?
            case .text: return entry.content as NSString?
            }
        }
        guard !items.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: items)
        sharingPicker = picker
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func createZIP(from entries: [ShelfEntry]) {
        let files = entries.map(\.url)
        guard !files.isEmpty else { return }
        let destination: URL
        do { destination = try store.makeTemporaryArchiveURL(for: files) }
        catch {
            showError("Could not prepare ZIP", error.localizedDescription)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ShelfOperations.createZIP(from: files, at: destination)
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else { return }
                    guard let id = self.store.addTemporaryArchive(destination) else {
                        self.store.discardTemporaryArchive(at: destination)
                        self.showError("Could not add ZIP", "The archive could not be added to the shelf.")
                        return
                    }
                    self.panel.orderFrontRegardless()
                    self.shelfView.scrollToEntry(id)
                    DispatchQueue.main.async { [weak self] in self?.shelfView.scrollToEntry(id) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else { return }
                    self?.store.discardTemporaryArchive(at: destination)
                    self?.showError("Could not create ZIP", error.localizedDescription)
                }
            }
        }
    }

    func resizeImage(_ entry: ShelfEntry) {
        let alert = NSAlert()
        alert.messageText = "Resize image"
        alert.informativeText = "Enter the width in pixels. Fallet keeps the original image."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 25))
        field.stringValue = "1200"
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let width = Int(field.stringValue), width > 0, width <= 16000 else {
            showError("Invalid image width", "Enter a number between 1 and 16000 pixels.")
            return
        }
        let picker = NSSavePanel()
        picker.allowedContentTypes = [.png]
        picker.nameFieldStringValue = entry.url.deletingPathExtension().lastPathComponent + "-resized.png"
        picker.prompt = "Save Resized Image"
        guard picker.runModal() == .OK, let destination = picker.url else { return }
        let source = entry.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try ShelfOperations.resizeImage(at: source, toWidth: width, saveTo: destination)
                DispatchQueue.main.async { self?.store.add([destination]) }
            } catch {
                DispatchQueue.main.async { self?.showError("Could not resize image", error.localizedDescription) }
            }
        }
    }

    func extractText(from entry: ShelfEntry) {
        let source = entry.url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let text = try ShelfOperations.recognizeText(in: source)
                DispatchQueue.main.async {
                    self?.store.addText(text)
                    self?.panel.orderFrontRegardless()
                }
            } catch {
                DispatchQueue.main.async { self?.showError("Could not extract text", error.localizedDescription) }
            }
        }
    }

    func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
#endif
