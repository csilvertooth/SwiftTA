//
//  UnitBrowser.swift
//  TAassets
//
//  Created by Logan Jones on 1/22/17.
//  Copyright © 2017 Logan Jones. All rights reserved.
//

import Cocoa
import SwiftTA_Core

class UnitBrowserViewController: NSViewController, ContentViewController {

    var shared = TaassetsSharedState.empty
    private var allUnits: [UnitInfo] = []
    private var units: [UnitInfo] = []
    private var textures = ModelTexturePack()
    private var searchTerm: String = ""

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var detailViewContainer: NSView!
    private let detailViewController = UnitDetailViewController()
    private var isShowingDetail = false

    static let picSize: CGFloat = 64

    override func loadView() {
        let bounds = NSRect(x: 0, y: 0, width: 480, height: 480)
        let mainView = NSView(frame: bounds)

        let listWidth: CGFloat = 240
        let searchHeight: CGFloat = 28

        let searchField = NSSearchField(frame: NSMakeRect(4, bounds.size.height - searchHeight - 2, listWidth - 8, searchHeight - 4))
        searchField.autoresizingMask = [.minYMargin]
        searchField.placeholderString = "Filter units"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        mainView.addSubview(searchField)

        let scrollView = NSScrollView(frame: NSMakeRect(0, 0, listWidth, bounds.size.height - searchHeight))
        scrollView.autoresizingMask = [.height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let tableView = NSTableView(frame: NSMakeRect(0, 0, listWidth, bounds.size.height - searchHeight))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "name"))
        column.width = listWidth-2
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier(rawValue: "units")
        tableView.headerView = nil
        tableView.rowHeight = UnitBrowserViewController.picSize

        scrollView.documentView = tableView

        tableView.dataSource = self
        tableView.delegate = self
        mainView.addSubview(scrollView)

        let detail = NSView(frame: NSMakeRect(listWidth, 0, bounds.size.width - listWidth, bounds.size.height))
        detail.autoresizingMask = [.width, .height]
        mainView.addSubview(detail)

        self.view = mainView
        self.detailViewContainer = detail
        self.tableView = tableView
        self.searchField = searchField
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        searchTerm = sender.stringValue.trimmingCharacters(in: .whitespaces)
        applyFilter()
    }

    private func applyFilter() {
        if searchTerm.isEmpty {
            units = allUnits
        } else {
            let term = searchTerm.lowercased()
            units = allUnits.filter {
                $0.name.lowercased().contains(term)
                    || $0.title.lowercased().contains(term)
                    || $0.description.lowercased().contains(term)
                    || $0.object.lowercased().contains(term)
            }
        }
        tableView.reloadData()
    }
    
    override func viewDidLoad() {
        let begin = Date()

        let rootNames = shared.filesystem.root.items.map { $0.name }.sorted()
        print("Filesystem root contains \(rootNames.count) entries: \(rootNames.prefix(40).joined(separator: ", "))\(rootNames.count > 40 ? "…" : "")")

        var perDir: [(String, Int)] = []
        for item in shared.filesystem.root.items {
            if case .directory(let d) = item {
                let count = d.allFiles(withExtension: "fbi").count
                if count > 0 { perDir.append((d.name, count)) }
            }
        }
        perDir.sort { $0.1 > $1.1 }
        if !perDir.isEmpty {
            let summary = perDir.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
            print("FBI counts per top-level dir: \(summary)")
        }

        let fbiFiles = shared.filesystem.root.allFiles(withExtension: "fbi")

        var seenNames = Set<String>()
        let units = fbiFiles
            .sorted { FileSystem.sortNames($0.name, $1.name) }
            .filter { seenNames.insert($0.baseName.lowercased()).inserted }
            .compactMap { try? shared.filesystem.openFile($0) }
            .compactMap { try? UnitInfo(contentsOf: $0) }
        self.allUnits = units
        self.units = units
        let end = Date()
        print("UnitInfo list load time: \(end.timeIntervalSince(begin)) seconds; units found: \(units.count) (from \(fbiFiles.count) FBI files)")

        textures = ModelTexturePack(loadFrom: shared.filesystem)
    }
    
    final func buildpic(for unitName: String) -> NSImage? {
        let fs = shared.filesystem

        let pictureDirs = fs.root.items.compactMap { item -> FileSystem.Directory? in
            guard case .directory(let d) = item else { return nil }
            return d.name.lowercased().hasPrefix("unitpic") ? d : nil
        }

        for dir in pictureDirs {
            if let file = dir[file: unitName + ".pcx"],
               let handle = try? fs.openFile(file),
               let image = try? NSImage(pcxContentsOf: handle) {
                return image
            }
            for ext in ["bmp", "png", "jpg", "jpeg", "tga"] {
                if let file = dir[file: unitName + "." + ext],
                   let handle = try? fs.openFile(file) {
                    let data = handle.readDataToEndOfFile()
                    if let image = NSImage(data: data) { return image }
                }
            }
        }

        for ext in ["jpg", "jpeg", "png", "bmp"] {
            if let file = try? fs.openFile(at: "anims/buildpic/" + unitName + "." + ext) {
                let data = file.readDataToEndOfFile()
                if let image = NSImage(data: data) { return image }
            }
        }

        return nil
    }
    
}

extension UnitBrowserViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return units.count
    }
    
}

extension UnitBrowserViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let cell: UnitInfoCell
        if let existing = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "UnitInfo"), owner: self) as? UnitInfoCell {
            cell = existing
        }
        else {
            cell = UnitInfoCell()
            cell.identifier = NSUserInterfaceItemIdentifier(rawValue: "UnitInfo")
        }
        
        let unit = units[row]
        cell.name = unit.name
        cell.title = unit.title
        cell.descriptionText = unit.description
        cell.buildpic = buildpic(for: unit.name)
        return cell
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView
            else { return }
        let row = tableView.selectedRow
        if row >= 0 {
            
            if !isShowingDetail {
                let controller = detailViewController
                controller.view.frame = detailViewContainer.bounds
                controller.view.autoresizingMask = [.width, .height]
                addChild(controller)
                detailViewContainer.addSubview(controller.view)
                isShowingDetail = true
            }
            
            detailViewController.shared = UnitBrowserSharedState(filesystem: shared.filesystem, textures: textures, sides: shared.sides)
            do { try detailViewController.load(units[row]) }
            catch { print("!!! Failed to load \(units[row].name): \(error)") }
        }
        else if isShowingDetail {
            detailViewController.clear()
            detailViewController.view.removeFromSuperview()
            detailViewController.removeFromParent()
            isShowingDetail = false
        }
    }
    
}

class UnitInfoCell: NSTableCellView {
    
    private var picView: NSImageView!
    private var nameField: NSTextField!
    private var titleField: NSTextField!
    private var descriptionField: NSTextField!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        picView = NSImageView()
        picView.translatesAutoresizingMaskIntoConstraints = false
        picView.imageScaling = .scaleProportionallyUpOrDown
        self.addSubview(picView)
        
        nameField = NSTextField(labelWithString: "")
        nameField.font = NSFont.systemFont(ofSize: 14)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(nameField)
        
        titleField = NSTextField(labelWithString: "")
        titleField.font = NSFont.systemFont(ofSize: 12)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(titleField)
        
        descriptionField = NSTextField(labelWithString: "")
        descriptionField.font = NSFont.systemFont(ofSize: 8)
        descriptionField.textColor = NSColor.secondaryLabelColor
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(descriptionField)
        
        NSLayoutConstraint.activate([
            picView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            picView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            picView.widthAnchor.constraint(equalToConstant: UnitBrowserViewController.picSize),
            picView.heightAnchor.constraint(equalToConstant: UnitBrowserViewController.picSize),
            
            nameField.leadingAnchor.constraint(equalTo: picView.trailingAnchor, constant: 8),
            nameField.topAnchor.constraint(equalTo: picView.topAnchor),
            
            titleField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            titleField.topAnchor.constraint(equalTo: nameField.bottomAnchor),
            
            descriptionField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            descriptionField.topAnchor.constraint(equalTo: titleField.bottomAnchor),
            ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var name: String {
        get { return nameField?.stringValue ?? "" }
        set { nameField.stringValue = newValue }
    }
    var title: String {
        get { return titleField?.stringValue ?? "" }
        set { titleField.stringValue = newValue }
    }
    var descriptionText: String {
        get { return descriptionField?.stringValue ?? "" }
        set { descriptionField.stringValue = newValue }
    }
    var buildpic: NSImage? {
        get { return picView.image }
        set { picView.image = newValue }
    }
    
}

struct UnitBrowserSharedState {
    unowned let filesystem: FileSystem
    unowned let textures: ModelTexturePack
    let sides: [SideInfo]
}
extension UnitBrowserSharedState {
    static var empty: UnitBrowserSharedState {
        return UnitBrowserSharedState(filesystem: FileSystem(), textures: ModelTexturePack(), sides: [])
    }
}

class UnitDetailViewController: NSViewController, PieceHierarchyViewDelegate, PlaybackControlsViewDelegate {

    var shared = UnitBrowserSharedState.empty
    let unitView = UnitViewController()
    let pieceView = PieceHierarchyView(frame: .zero)
    let playbackControls = PlaybackControlsView(frame: .zero)

    func pieceHierarchyView(_ view: PieceHierarchyView, didSelectPieceAt index: UnitModel.Pieces.Index?) {
        unitView.setHighlightedPiece(index)
    }

    func playbackControls(_ view: PlaybackControlsView, didChangeSpeed speed: Float) {
        unitView.setPlaybackSpeed(speed)
    }
    func playbackControlsDidRequestStep(_ view: PlaybackControlsView) {
        unitView.stepOnce()
    }
    func playbackControls(_ view: PlaybackControlsView, didChooseScript name: String) {
        unitView.startScript(name)
    }

    func load(_ unit: UnitInfo) throws {
        unitTitle = unit.object.isEmpty ? unit.name : unit.object
        container.detailLabel.stringValue = Self.describe(unit)
        let modelFile = try shared.filesystem.openFile(at: "objects3d/" + unit.object + ".3DO")
        let model = try UnitModel(contentsOf: modelFile)
        let scriptFile = try shared.filesystem.openFile(at: "scripts/" + unit.object + ".COB")
        let script = try UnitScript(contentsOf: scriptFile)
        let atlas = UnitTextureAtlas(for: model.textures, from: shared.textures)
        let palette = resolvePalette(for: unit)

        let pieceNames = model.pieces.enumerated().map { "[\($0.offset)]\($0.element.name)" }.joined(separator: " ")
        print("Unit \(unit.object): \(model.pieces.count) pieces, \(model.primitives.count) primitives, \(script.modules.count) script modules")
        print("  pieces: \(pieceNames)")

        try unitView.load(unit, model, script, atlas, shared.filesystem, palette)
        pieceView.apply(model: model, script: script)
        playbackControls.reset(scriptFunctions: unitView.availableScriptFunctions)

        //try tempSaveAtlasToFile(atlas, palette)
    }

    func clear() {
        unitView.clear()
        pieceView.clear()
        playbackControls.reset(scriptFunctions: [])
        container.titleLabel.stringValue = ""
        container.detailLabel.stringValue = ""
    }

    private static func describe(_ unit: UnitInfo) -> String {
        var parts: [String] = []
        if !unit.title.isEmpty { parts.append(unit.title) }
        if !unit.description.isEmpty { parts.append(unit.description) }
        if !unit.side.isEmpty { parts.append(unit.side) }
        if !unit.tedClass.isEmpty { parts.append(unit.tedClass) }
        parts.append("footprint \(unit.footprint.width)×\(unit.footprint.height)")
        if unit.maxVelocity > 0 {
            parts.append(String(format: "speed %.1f", Double(unit.maxVelocity)))
        }
        return parts.joined(separator: " · ")
    }

    private func resolvePalette(for unit: UnitInfo) -> Palette {
        if let p = try? Palette.texturePalette(for: unit, in: shared.sides, from: shared.filesystem) {
            return p
        }
        if let p = try? Palette.standardTaPalette(from: shared.filesystem) {
            return p.applyingChromaKeys(Palette.textureTransparencies)
        }
        return Palette()
    }
    
    private func tempSaveAtlasToFile(_ atlas: UnitTextureAtlas, _ palette: Palette) throws {
        let pixelData = atlas.build(from: shared.filesystem, using: palette)
        
        let cfdata = pixelData.withUnsafeBytes { (pixels: UnsafeRawBufferPointer) -> CFData in
            return CFDataCreate(kCFAllocatorDefault, pixels.bindMemory(to: UInt8.self).baseAddress!, pixelData.count)
        }
        let image = CGImage(width: atlas.size.width,
                            height: atlas.size.height,
                            bitsPerComponent: 8,
                            bitsPerPixel: 32,
                            bytesPerRow: atlas.size.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: [],
                            provider: CGDataProvider(data: cfdata)!,
                            decode: nil,
                            shouldInterpolate: false,
                            intent: .defaultIntent)
        //let image2 = NSImage(cgImage: image!, size: NSSize(width: atlas.size.width, height: atlas.size.height))
        
        let rep = NSBitmapImageRep(cgImage: image!)
        rep.size = NSSize(width: atlas.size.width, height: atlas.size.height)
        let fileData = rep.representation(using: .png, properties: [:])
        let url2 = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").appendingPathComponent("test.png")
        try fileData?.write(to: url2, options: .atomic)
    }
    
    var unitTitle: String {
        get { return container.titleLabel.stringValue }
        set(new) { container.titleLabel.stringValue = new }
    }
    
    private var container: ContainerView {
        return view as! ContainerView
    }
    
    private class ContainerView: NSView {

        unowned let titleLabel: NSTextField
        unowned let detailLabel: NSTextField
        let emptyContentView: NSView
        let pieceAccessory: NSView

        weak var contentView: NSView? {
            didSet {
                guard contentView != oldValue else { return }
                oldValue?.removeFromSuperview()
                if let contentView = contentView {
                    addSubview(contentView)
                    contentView.translatesAutoresizingMaskIntoConstraints = false
                    addContentViewConstraints(contentView)
                }
                else {
                    oldValue?.removeFromSuperview()
                    addSubview(emptyContentView)
                    addContentViewConstraints(emptyContentView)
                }
            }
        }

        init(frame frameRect: NSRect, pieceAccessory: NSView) {
            let titleLabel = NSTextField(labelWithString: "")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = NSColor.labelColor
            titleLabel.lineBreakMode = .byTruncatingMiddle

            let detailLabel = NSTextField(labelWithString: "")
            detailLabel.font = NSFont.systemFont(ofSize: 11)
            detailLabel.textColor = NSColor.secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail

            let contentBox = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))

            self.titleLabel = titleLabel
            self.detailLabel = detailLabel
            self.emptyContentView = contentBox
            self.pieceAccessory = pieceAccessory
            super.init(frame: frameRect)

            addSubview(contentBox)
            addSubview(titleLabel)
            addSubview(detailLabel)
            pieceAccessory.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pieceAccessory)

            contentBox.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.translatesAutoresizingMaskIntoConstraints = false

            addContentViewConstraints(contentBox)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
                detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
                detailLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                detailLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
                pieceAccessory.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                pieceAccessory.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                pieceAccessory.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func addContentViewConstraints(_ contentBox: NSView) {
            NSLayoutConstraint.activate([
                contentBox.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                contentBox.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                contentBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                contentBox.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.55),
                pieceAccessory.topAnchor.constraint(equalTo: contentBox.bottomAnchor, constant: 6),
                ])
        }

    }

    override func loadView() {
        let stack = NSStackView(views: [playbackControls, pieceView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .vertical)
        pieceView.translatesAutoresizingMaskIntoConstraints = false
        playbackControls.translatesAutoresizingMaskIntoConstraints = false
        stack.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = ContainerView(frame: NSRect(x: 0, y: 0, width: 256, height: 512),
                                      pieceAccessory: stack)
        self.view = container

        addChild(unitView)
        container.contentView = unitView.view
        pieceView.selectionDelegate = self
        playbackControls.delegate = self
    }
    
}
