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
    private let toolSegmented: NSSegmentedControl
    private let brushRadiusSlider: NSSlider
    private let brushStrengthSlider: NSSlider
    private let radiusLabel: NSTextField
    private let strengthLabel: NSTextField
    private let modeSegmented: NSSegmentedControl
    private let featurePopup: NSPopUpButton
    private let addFeatureButton: NSButton
    private let tilePopup: NSPopUpButton
    private let tilePreview: NSImageView
    private let heightsGroup: NSStackView
    private let featuresGroup: NSStackView
    private let tilesGroup: NSStackView
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

        let toolSegmented = NSSegmentedControl(labels: ["Heights", "Features", "Tiles"], trackingMode: .selectOne, target: nil, action: nil)
        toolSegmented.selectedSegment = 0
        toolSegmented.controlSize = .regular

        let modeSegmented = NSSegmentedControl(labels: ["Raise", "Lower"], trackingMode: .selectOne, target: nil, action: nil)
        modeSegmented.selectedSegment = 0
        modeSegmented.controlSize = .regular

        let radiusLabel = NSTextField(labelWithString: "Radius: 3")
        let brushRadiusSlider = NSSlider(value: 3, minValue: 0, maxValue: 32, target: nil, action: nil)
        brushRadiusSlider.isContinuous = true

        let strengthLabel = NSTextField(labelWithString: "Strength: 16")
        let brushStrengthSlider = NSSlider(value: 16, minValue: 1, maxValue: 127, target: nil, action: nil)
        brushStrengthSlider.isContinuous = true

        let featurePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24), pullsDown: false)
        for featureId in map.model.features {
            featurePopup.addItem(withTitle: featureId.name)
        }
        if map.model.features.isEmpty {
            featurePopup.addItem(withTitle: "(no features in map)")
            featurePopup.isEnabled = false
        }

        let addFeatureButton = NSButton(title: "Add feature type…", target: nil, action: nil)
        addFeatureButton.bezelStyle = .rounded
        addFeatureButton.controlSize = .regular

        let featureHint = NSTextField(wrappingLabelWithString: "Left-click a cell to place the selected feature. Right-click to remove any feature at the clicked cell.")
        featureHint.font = NSFont.systemFont(ofSize: 10)
        featureHint.textColor = .secondaryLabelColor

        let tilePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 24), pullsDown: false)
        MapEditorWindowController.populateTilePopup(tilePopup, map: map)

        let tilePreview = NSImageView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
        tilePreview.imageScaling = .scaleProportionallyUpOrDown
        tilePreview.image = MapRasterizer.renderTile(index: 0, in: map.model, using: map.palette)

        let tileHint = NSTextField(wrappingLabelWithString: "Pick a tile in the dropdown, then click on the map to paint that tile at the clicked 32×32 cell.")
        tileHint.font = NSFont.systemFont(ofSize: 10)
        tileHint.textColor = .secondaryLabelColor

        self.mapInfoLabel = mapInfoLabel
        self.toolSegmented = toolSegmented
        self.modeSegmented = modeSegmented
        self.brushRadiusSlider = brushRadiusSlider
        self.brushStrengthSlider = brushStrengthSlider
        self.radiusLabel = radiusLabel
        self.strengthLabel = strengthLabel
        self.featurePopup = featurePopup
        self.addFeatureButton = addFeatureButton
        self.tilePopup = tilePopup
        self.tilePreview = tilePreview

        let heightsGroup = NSStackView(views: [modeSegmented, radiusLabel, brushRadiusSlider, strengthLabel, brushStrengthSlider])
        heightsGroup.orientation = .vertical
        heightsGroup.alignment = .leading
        heightsGroup.spacing = 8

        let featuresGroup = NSStackView(views: [featurePopup, addFeatureButton, featureHint])
        featuresGroup.orientation = .vertical
        featuresGroup.alignment = .leading
        featuresGroup.spacing = 8
        featuresGroup.isHidden = true

        let tilesGroup = NSStackView(views: [tilePopup, tilePreview, tileHint])
        tilesGroup.orientation = .vertical
        tilesGroup.alignment = .leading
        tilesGroup.spacing = 8
        tilesGroup.isHidden = true

        self.heightsGroup = heightsGroup
        self.featuresGroup = featuresGroup
        self.tilesGroup = tilesGroup

        canvas = MapCanvasView(frame: NSRect(x: paletteWidth, y: 0, width: windowFrame.width - paletteWidth, height: windowFrame.height))
        canvas.autoresizingMask = [.width, .height]
        canvas.map = map

        super.init(window: window)

        // Lay out the palette contents now that self exists and can target actions.
        toolSegmented.target = self
        toolSegmented.action = #selector(toolChanged(_:))
        modeSegmented.target = self
        modeSegmented.action = #selector(modeChanged(_:))
        brushRadiusSlider.target = self
        brushRadiusSlider.action = #selector(radiusChanged(_:))
        brushStrengthSlider.target = self
        brushStrengthSlider.action = #selector(strengthChanged(_:))
        addFeatureButton.target = self
        addFeatureButton.action = #selector(addFeatureTypePrompt(_:))
        tilePopup.target = self
        tilePopup.action = #selector(tileSelectionChanged(_:))

        let stack = NSStackView(views: [mapInfoLabel, toolSegmented, heightsGroup, featuresGroup, tilesGroup])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        palette.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: palette.topAnchor),
            stack.leadingAnchor.constraint(equalTo: palette.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: palette.trailingAnchor),
            toolSegmented.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            brushRadiusSlider.widthAnchor.constraint(equalTo: heightsGroup.widthAnchor),
            brushStrengthSlider.widthAnchor.constraint(equalTo: heightsGroup.widthAnchor),
            heightsGroup.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            featuresGroup.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            featurePopup.widthAnchor.constraint(equalTo: featuresGroup.widthAnchor),
            tilesGroup.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            tilePopup.widthAnchor.constraint(equalTo: tilesGroup.widthAnchor),
            tilePreview.widthAnchor.constraint(equalToConstant: 96),
            tilePreview.heightAnchor.constraint(equalToConstant: 96),
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

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        let tool: MapCanvasTool
        switch sender.selectedSegment {
        case 1: tool = .features
        case 2: tool = .tiles
        default: tool = .heights
        }
        canvas.activeTool = tool
        heightsGroup.isHidden = tool != .heights
        featuresGroup.isHidden = tool != .features
        tilesGroup.isHidden = tool != .tiles
    }

    @objc private func tileSelectionChanged(_ sender: NSPopUpButton) {
        canvas.selectedTileIndex = sender.indexOfSelectedItem
        tilePreview.image = MapRasterizer.renderTile(index: canvas.selectedTileIndex, in: map.model, using: map.palette)
    }

    /// Fills a popup with tile entries: "Tile N" titles, sorted numerically.
    /// Keeping this in its own static so initializer code can call it
    /// before `self` is fully constructed.
    private static func populateTilePopup(_ popup: NSPopUpButton, map: EditableMap) {
        popup.removeAllItems()
        let count = map.model.tileSet.count
        guard count > 0 else {
            popup.addItem(withTitle: "(no tiles in map)")
            popup.isEnabled = false
            return
        }
        popup.isEnabled = true
        for i in 0..<count {
            popup.addItem(withTitle: "Tile \(i)")
            if let image = MapRasterizer.renderTile(index: i, in: map.model, using: map.palette) {
                popup.item(at: i)?.image = image
            }
        }
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        canvas.eraseMode = sender.selectedSegment == 1
    }

    @objc private func addFeatureTypePrompt(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Add a feature type"
        alert.informativeText = "Enter the exact feature name (from FBI / features TDF) to add to this map's feature table."

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "e.g. Tree01, MetalPatch, SmallRock01"
        alert.accessoryView = textField

        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        // Focus the text field so the user can start typing immediately.
        DispatchQueue.main.async { textField.window?.makeFirstResponder(textField) }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Run the append command through the undo stack so this is
        // reversible. We also record the command so future assigns to the
        // new index come AFTER this append in the history.
        let command = FeatureTypeAppendCommand(featureName: trimmed)
        registerNewUndoableCommand(command)

        rebuildFeaturePopup(selecting: map.model.features.count - 1)
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
        // The canvas already applied the command when the stroke ended;
        // we only need to record undo here. registerNewUndoableCommand
        // handles the cycle for both new actions and clicks from feature
        // tool.
        registerUndoForAlreadyAppliedCommand(command)
        refreshTitle()
        rebuildFeaturePopup()
    }

    func canvasDidModifyMap() {
        refreshTitle()
    }

    func canvasWantsFeatureAssignment(forCell index: Int) -> Int?? {
        // The popup holds an entry per features[] slot; selecting index N
        // means "place features[N]". If the user hasn't added any feature
        // types yet, there's nothing to place and the click is a no-op.
        guard !map.model.features.isEmpty, featurePopup.isEnabled else { return nil }
        let selected = featurePopup.indexOfSelectedItem
        guard selected >= 0, selected < map.model.features.count else { return nil }
        return .some(selected)
    }

    /// Runs `command.apply(on:)` AND registers the undo for it. Used by
    /// the Add Feature Type path which isn't called from a stroke end.
    private func registerNewUndoableCommand(_ command: MapCommand) {
        command.apply(to: map)
        registerUndoForAlreadyAppliedCommand(command)
        canvas.needsDisplay = true
        refreshTitle()
    }

    private func registerUndoForAlreadyAppliedCommand(_ command: MapCommand) {
        undoManagerLocal.registerUndo(withTarget: self) { target in
            command.revert(on: target.map)
            target.canvas.invalidateTileRaster()
            target.rebuildFeaturePopup()
            target.refreshTitle()
            target.registerRedo(command)
        }
    }

    private func registerRedo(_ command: MapCommand) {
        undoManagerLocal.registerUndo(withTarget: self) { target in
            command.apply(to: target.map)
            target.canvas.invalidateTileRaster()
            target.rebuildFeaturePopup()
            target.refreshTitle()
            target.registerUndoForAlreadyAppliedCommand(command)
        }
    }

    // MARK: - UI plumbing

    private func rebuildFeaturePopup(selecting index: Int? = nil) {
        let previousIndex = featurePopup.indexOfSelectedItem
        featurePopup.removeAllItems()
        for featureId in map.model.features {
            featurePopup.addItem(withTitle: featureId.name)
        }
        if map.model.features.isEmpty {
            featurePopup.addItem(withTitle: "(no features in map)")
            featurePopup.isEnabled = false
        } else {
            featurePopup.isEnabled = true
            let target = index ?? previousIndex
            if target >= 0 && target < map.model.features.count {
                featurePopup.selectItem(at: target)
            }
        }
    }

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
