//
//  MapBrowser.swift
//  TAassets
//
//  Created by Logan Jones on 6/4/17.
//  Copyright © 2017 Logan Jones. All rights reserved.
//

import Cocoa
import SwiftTA_Core

class MapBrowserViewController: NSViewController, ContentViewController {

    var shared = TaassetsSharedState.empty
    private var allMaps: [FileSystem.File] = []
    private var maps: [FileSystem.File] = []
    private var searchTerm: String = ""

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var detailViewContainer: NSView!
    private var detailViewController = MapDetailViewController()
    private var isShowingDetail = false

    override func loadView() {
        let bounds = NSRect(x: 0, y: 0, width: 480, height: 480)
        let mainView = NSView(frame: bounds)

        let listWidth: CGFloat = 240
        let searchHeight: CGFloat = 28

        let searchField = NSSearchField(frame: NSMakeRect(4, bounds.size.height - searchHeight - 2, listWidth - 8, searchHeight - 4))
        searchField.autoresizingMask = [.minYMargin]
        searchField.placeholderString = "Filter maps"
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
        tableView.identifier = NSUserInterfaceItemIdentifier(rawValue: "maps")
        tableView.headerView = nil
        tableView.rowHeight = 32

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

    override func viewDidLoad() {
        let begin = Date()
        let mapsDirectory = shared.filesystem.root[directory: "maps"] ?? FileSystem.Directory()
        let maps = mapsDirectory.allFiles(withExtension: "ota")
            .sorted { FileSystem.sortNames($0.name, $1.name) }
        self.allMaps = maps
        self.maps = maps
        let end = Date()
        print("Map list load time: \(end.timeIntervalSince(begin)) seconds; maps found: \(maps.count)")
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        searchTerm = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if searchTerm.isEmpty {
            maps = allMaps
        } else {
            let term = searchTerm.lowercased()
            maps = allMaps.filter { $0.baseName.lowercased().contains(term) || $0.name.lowercased().contains(term) }
        }
        tableView.reloadData()
    }

}

extension MapBrowserViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return maps.count
    }
    
}

extension MapBrowserViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        let cell: MapInfoCell
        if let existing = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MapInfo"), owner: self) as? MapInfoCell {
            cell = existing
        }
        else {
            cell = MapInfoCell()
            cell.identifier = NSUserInterfaceItemIdentifier(rawValue: "MapInfo")
        }
        
        let file = maps[row]
        cell.name = file.baseName
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
            
            do { try detailViewController.loadMap(in: maps[row], from: shared.filesystem) }
            catch { print("!!! Failed to map \(maps[row].name): \(error)") }
        }
        else if isShowingDetail {
            detailViewController.clear()
            detailViewController.view.removeFromSuperview()
            detailViewController.removeFromParent()
            isShowingDetail = false
        }
    }
    
}

class MapInfoCell: NSTableCellView {
    
    private var nameField: NSTextField!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        nameField = NSTextField(labelWithString: "")
        nameField.font = NSFont.systemFont(ofSize: 14)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(nameField)
        
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var name: String {
        get { return nameField?.stringValue ?? "" }
        set { nameField.stringValue = newValue }
    }
    
}

class MapDetailViewController: NSViewController {

    let mapView = MapViewController()
    private var overlayMode: MapOverlayMode = .none
    private var slopeThreshold: Int = 20

    func loadMap(in otaFile: FileSystem.File, from filesystem: FileSystem) throws {
        let name = otaFile.baseName
        try mapView.load(name, from: filesystem)
        mapTitle = name
        mapView.setOverlayMode(overlayMode)
        mapView.setSlopeThreshold(slopeThreshold)

        if let info = try? MapInfo(contentsOf: otaFile, in: filesystem) {
            container.detailLabel.stringValue = Self.describe(info, mapName: name)
        } else {
            container.detailLabel.stringValue = ""
        }
    }

    func clear() {
        mapView.clear()
        container.titleLabel.stringValue = ""
        container.detailLabel.stringValue = ""
    }

    @objc private func overlayModeChanged(_ sender: NSSegmentedControl) {
        guard let mode = MapOverlayMode(rawValue: sender.selectedSegment) else { return }
        overlayMode = mode
        mapView.setOverlayMode(mode)
        container.setSlopeControlVisible(mode == .passability)
    }

    @objc private func slopeThresholdChanged(_ sender: NSSlider) {
        let value = Int(sender.integerValue)
        slopeThreshold = value
        container.updateSlopeLabel(value)
        mapView.setSlopeThreshold(value)
    }

    var mapTitle: String {
        get { return container.titleLabel.stringValue }
        set(new) { container.titleLabel.stringValue = new }
    }

    private static func describe(_ info: MapInfo, mapName: String) -> String {
        var parts: [String] = []
        let primary = (info.name.isEmpty ? mapName : info.name)
        if primary.lowercased() != mapName.lowercased() {
            parts.append(primary)
        }
        if let planet = info.planet, !planet.isEmpty { parts.append(planet) }
        if let schema = info.schema.first {
            parts.append("\(schema.startPositions.count) players")
        }
        parts.append("wind \(info.windSpeed.lowerBound)-\(info.windSpeed.upperBound)")
        parts.append("tidal \(info.tidalStrength)")
        parts.append("gravity \(info.gravity)")
        return parts.joined(separator: " · ")
    }

    private var container: ContainerView {
        return view as! ContainerView
    }
    
    fileprivate class ContainerView: NSView {

        unowned let titleLabel: NSTextField
        unowned let detailLabel: NSTextField
        unowned let overlayControl: NSSegmentedControl
        unowned let slopeSlider: NSSlider
        unowned let slopeLabel: NSTextField
        let emptyContentView: NSView

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

        func setSlopeControlVisible(_ visible: Bool) {
            slopeSlider.isHidden = !visible
            slopeLabel.isHidden = !visible
        }

        func updateSlopeLabel(_ value: Int) {
            slopeLabel.stringValue = "slope ≤ \(value)"
        }

        override init(frame frameRect: NSRect) {
            let titleLabel = NSTextField(labelWithString: "")
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = NSColor.labelColor
            titleLabel.lineBreakMode = .byTruncatingMiddle

            let detailLabel = NSTextField(labelWithString: "")
            detailLabel.font = NSFont.systemFont(ofSize: 11)
            detailLabel.textColor = NSColor.secondaryLabelColor
            detailLabel.lineBreakMode = .byTruncatingTail

            let overlayControl = NSSegmentedControl(labels: MapOverlayMode.allCases.map { $0.title },
                                                    trackingMode: .selectOne,
                                                    target: nil,
                                                    action: nil)
            overlayControl.selectedSegment = 0
            overlayControl.controlSize = .small
            overlayControl.segmentStyle = .rounded

            let slopeSlider = NSSlider(value: 20, minValue: 1, maxValue: 120, target: nil, action: nil)
            slopeSlider.controlSize = .small
            slopeSlider.isContinuous = true
            slopeSlider.isHidden = true

            let slopeLabel = NSTextField(labelWithString: "slope ≤ 20")
            slopeLabel.font = NSFont.systemFont(ofSize: 11)
            slopeLabel.textColor = NSColor.secondaryLabelColor
            slopeLabel.isHidden = true

            let contentBox = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))

            self.titleLabel = titleLabel
            self.detailLabel = detailLabel
            self.overlayControl = overlayControl
            self.slopeSlider = slopeSlider
            self.slopeLabel = slopeLabel
            self.emptyContentView = contentBox
            super.init(frame: frameRect)

            addSubview(contentBox)
            addSubview(titleLabel)
            addSubview(detailLabel)
            addSubview(overlayControl)
            addSubview(slopeSlider)
            addSubview(slopeLabel)

            contentBox.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.translatesAutoresizingMaskIntoConstraints = false
            overlayControl.translatesAutoresizingMaskIntoConstraints = false
            slopeSlider.translatesAutoresizingMaskIntoConstraints = false
            slopeLabel.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
                detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
                detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: overlayControl.leadingAnchor, constant: -12),
                detailLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

                overlayControl.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                overlayControl.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),

                slopeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                slopeLabel.trailingAnchor.constraint(equalTo: overlayControl.trailingAnchor),
                slopeSlider.centerYAnchor.constraint(equalTo: slopeLabel.centerYAnchor),
                slopeSlider.trailingAnchor.constraint(equalTo: slopeLabel.leadingAnchor, constant: -6),
                slopeSlider.widthAnchor.constraint(equalToConstant: 120),
                ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func addContentViewConstraints(_ contentBox: NSView) {
            NSLayoutConstraint.activate([
                contentBox.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
                contentBox.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4),
                contentBox.topAnchor.constraint(equalTo: overlayControl.bottomAnchor, constant: 6),
                contentBox.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
                ])
        }

    }

    override func loadView() {
        let container = ContainerView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        self.view = container

        container.overlayControl.target = self
        container.overlayControl.action = #selector(overlayModeChanged(_:))
        container.slopeSlider.target = self
        container.slopeSlider.action = #selector(slopeThresholdChanged(_:))

        addChild(mapView)
        container.contentView = mapView.view
    }
    
}
