//
//  MapEditorWindowController.swift
//  AEX-MapEditor
//
//  Wires up one window per open map. The window holds a side panel for
//  the tool palette + brush config and a central MapCanvasView for the
//  actual painting surface. Undo / redo live on an NSUndoManager local
//  to this window so each open map has its own undo history.
//

import Cocoa
import SwiftTA_Core


final class MapEditorWindowController: NSWindowController, MapCanvasViewDelegate {

    private let map: EditableMap
    private let canvas: MapCanvasView
    private let brushRadiusSlider: NSSlider
    private let brushStrengthSlider: NSSlider
    private let radiusLabel: NSTextField
    private let strengthLabel: NSTextField
    private let modeSegmented: NSSegmentedControl
    private let mapInfoLabel: NSTextField
    private let undoManagerLocal = UndoManager()

    init(mapURL: URL) throws {
        let map = try EditableMap(loadingFrom: mapURL)
        self.map = map

        let windowFrame = NSRect(x: 0, y: 0, width: 1000, height: 720)
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = mapURL.lastPathComponent
        window.setFrameAutosaveName("AEX-MapEditor.window")

        // Tool palette on the left.
        let paletteWidth: CGFloat = 220
        let palette = NSView(frame: NSRect(x: 0, y: 0, width: paletteWidth, height: windowFrame.height))
        palette.autoresizingMask = [.height]

        let mapInfoLabel = NSTextField(labelWithString: "")
        mapInfoLabel.font = NSFont.systemFont(ofSize: 11)
        mapInfoLabel.textColor = .secondaryLabelColor
        mapInfoLabel.lineBreakMode = .byWordWrapping
        mapInfoLabel.maximumNumberOfLines = 3

        let modeSegmented = NSSegmentedControl(labels: ["Raise", "Lower"], trackingMode: .selectOne, target: nil, action: nil)
        modeSegmented.selectedSegment = 0
        modeSegmented.controlSize = .regular

        let radiusLabel = NSTextField(labelWithString: "Radius: 3")
        let brushRadiusSlider = NSSlider(value: 3, minValue: 0, maxValue: 32, target: nil, action: nil)
        brushRadiusSlider.isContinuous = true

        let strengthLabel = NSTextField(labelWithString: "Strength: 16")
        let brushStrengthSlider = NSSlider(value: 16, minValue: 1, maxValue: 127, target: nil, action: nil)
        brushStrengthSlider.isContinuous = true

        self.mapInfoLabel = mapInfoLabel
        self.modeSegmented = modeSegmented
        self.brushRadiusSlider = brushRadiusSlider
        self.brushStrengthSlider = brushStrengthSlider
        self.radiusLabel = radiusLabel
        self.strengthLabel = strengthLabel

        canvas = MapCanvasView(frame: NSRect(x: paletteWidth, y: 0, width: windowFrame.width - paletteWidth, height: windowFrame.height))
        canvas.autoresizingMask = [.width, .height]
        canvas.map = map

        super.init(window: window)

        // Lay out the palette contents now that self exists and can target actions.
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        brushRadiusSlider.target = self
        brushRadiusSlider.action = #selector(radiusChanged(_:))
        brushStrengthSlider.target = self
        brushStrengthSlider.action = #selector(strengthChanged(_:))

        let stack = NSStackView(views: [mapInfoLabel, modeSegmented, radiusLabel, brushRadiusSlider, strengthLabel, brushStrengthSlider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        palette.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: palette.topAnchor),
            stack.leadingAnchor.constraint(equalTo: palette.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: palette.trailingAnchor),
            brushRadiusSlider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            brushStrengthSlider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])

        let container = NSView(frame: windowFrame)
        container.autoresizingMask = [.width, .height]
        container.addSubview(palette)
        container.addSubview(canvas)

        // Thin vertical separator between palette and canvas.
        let divider = NSBox(frame: NSRect(x: paletteWidth - 1, y: 0, width: 1, height: windowFrame.height))
        divider.boxType = .separator
        divider.autoresizingMask = [.height]
        container.addSubview(divider)

        window.contentView = container
        window.contentMinSize = NSSize(width: 600, height: 400)

        canvas.delegate = self
        updateMapInfoLabel()
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var windowNibName: NSNib.Name? { nil }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.windowController = self
    }

    override var window: NSWindow? {
        get { super.window }
        set {
            super.window = newValue
            newValue?.windowController = self
        }
    }

    // MARK: - Tool palette actions

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        canvas.eraseMode = sender.selectedSegment == 1
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        canvas.brushRadius = Int(sender.integerValue)
        radiusLabel.stringValue = "Radius: \(canvas.brushRadius)"
    }

    @objc private func strengthChanged(_ sender: NSSlider) {
        canvas.brushStrength = Int(sender.integerValue)
        strengthLabel.stringValue = "Strength: \(canvas.brushStrength)"
    }

    // MARK: - Save

    func saveMap() {
        do {
            try map.saveToCurrentLocation()
            refreshTitle()
        } catch {
            presentError(error, contextMessage: "Couldn't save \(map.fileURL.lastPathComponent)")
        }
    }

    func saveMapAs() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["tnt"]
        panel.nameFieldStringValue = map.fileURL.lastPathComponent
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.map.save(to: url, otaTo: nil)
                self.refreshTitle()
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                self.presentError(error, contextMessage: "Couldn't save \(url.lastPathComponent)")
            }
        }
    }

    // MARK: - Undo / redo

    func undoLastEdit() {
        if undoManagerLocal.canUndo { undoManagerLocal.undo() }
        canvas.needsDisplay = true
        refreshTitle()
    }

    func redoLastEdit() {
        if undoManagerLocal.canRedo { undoManagerLocal.redo() }
        canvas.needsDisplay = true
        refreshTitle()
    }

    // MARK: - MapCanvasViewDelegate

    func canvasDidFinishStroke(_ command: MapCommand) {
        undoManagerLocal.registerUndo(withTarget: self) { target in
            command.revert(on: target.map)
            target.canvas.needsDisplay = true
            target.refreshTitle()
            target.undoManagerLocal.registerUndo(withTarget: target) { redoTarget in
                command.apply(to: redoTarget.map)
                redoTarget.canvas.needsDisplay = true
                redoTarget.refreshTitle()
                redoTarget.registerRedo(command)
            }
        }
        refreshTitle()
    }

    private func registerRedo(_ command: MapCommand) {
        undoManagerLocal.registerUndo(withTarget: self) { target in
            command.revert(on: target.map)
            target.canvas.needsDisplay = true
            target.refreshTitle()
        }
    }

    func canvasDidModifyMap() {
        refreshTitle()
    }

    // MARK: - UI plumbing

    private func updateMapInfoLabel() {
        let size = map.model.mapSize
        mapInfoLabel.stringValue = "\(map.fileURL.lastPathComponent)\n\(size.width)×\(size.height) cells  ·  sea level \(map.model.seaLevel)"
    }

    private func refreshTitle() {
        let base = map.fileURL.lastPathComponent
        window?.title = map.isModified ? "• " + base : base
        window?.representedURL = map.fileURL
        window?.isDocumentEdited = map.isModified
    }

    private func presentError(_ error: Error, contextMessage: String) {
        let alert = NSAlert()
        alert.messageText = contextMessage
        alert.informativeText = (error as NSError).localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window!) { _ in }
    }
}
