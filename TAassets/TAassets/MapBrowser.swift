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

    func loadMap(in otaFile: FileSystem.File, from filesystem: FileSystem) throws {
        let name = otaFile.baseName
        try mapView.load(name, from: filesystem)
        mapTitle = name

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
    
    private class ContainerView: NSView {

        unowned let titleLabel: NSTextField
        unowned let detailLabel: NSTextField
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

        override init(frame frameRect: NSRect) {
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
            super.init(frame: frameRect)

            addSubview(contentBox)
            addSubview(titleLabel)
            addSubview(detailLabel)

            contentBox.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            detailLabel.translatesAutoresizingMaskIntoConstraints = false

            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
                detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
                detailLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                detailLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
                ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func addContentViewConstraints(_ contentBox: NSView) {
            NSLayoutConstraint.activate([
                contentBox.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
                contentBox.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -4),
                contentBox.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                contentBox.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
                ])
        }

    }
    
    override func loadView() {
        let container = ContainerView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
        self.view = container
        
        addChild(mapView)
        container.contentView = mapView.view
    }
    
}
