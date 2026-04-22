//
//  PieceHierarchyView.swift
//  HPIView
//

import AppKit
import SwiftTA_Core

protocol PieceHierarchyViewDelegate: AnyObject {
    func pieceHierarchyView(_ view: PieceHierarchyView, didSelectPieceAt index: UnitModel.Pieces.Index?)
}

final class PieceHierarchyView: NSView {

    weak var selectionDelegate: PieceHierarchyViewDelegate?

    private let outline = NSOutlineView()
    private let scrollView = NSScrollView()
    private let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    private let detailColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("detail"))
    private let scriptsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scripts"))
    private var nodes: [Node] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        nameColumn.title = "Piece"
        nameColumn.minWidth = 120
        nameColumn.width = 200
        detailColumn.title = "Prims / Verts / Children"
        detailColumn.minWidth = 140
        detailColumn.width = 160
        scriptsColumn.title = "Script Refs"
        scriptsColumn.minWidth = 140
        scriptsColumn.width = 260
        outline.addTableColumn(nameColumn)
        outline.addTableColumn(detailColumn)
        outline.addTableColumn(scriptsColumn)
        outline.outlineTableColumn = nameColumn
        outline.rowSizeStyle = .small
        outline.usesAlternatingRowBackgroundColors = true
        outline.headerView = NSTableHeaderView()
        outline.dataSource = self
        outline.delegate = self
        outline.autoresizesOutlineColumn = false
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false

        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func apply(model: UnitModel, script: UnitScript? = nil) {
        let refsByScriptIndex = script?.pieceReferences() ?? [:]
        var refsByModelIndex: [UnitModel.Pieces.Index: String] = [:]
        if let script = script {
            for (scriptIdx, refs) in refsByScriptIndex {
                guard script.pieces.indices.contains(scriptIdx) else { continue }
                let name = script.pieces[scriptIdx].lowercased()
                guard let modelIdx = model.nameLookup[name] else { continue }
                let byModule = Dictionary(grouping: refs, by: \.moduleName)
                    .map { moduleName, calls -> String in
                        let ops = Set(calls.map { String(describing: $0.opcode) }).sorted().joined(separator: ",")
                        return "\(moduleName)[\(ops)]"
                    }
                    .sorted()
                refsByModelIndex[modelIdx] = byModule.joined(separator: " ")
            }
        }
        nodes = [Node(index: model.root, model: model, refs: refsByModelIndex)]
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
    }

    func clear() {
        nodes = []
        outline.reloadData()
    }

    fileprivate final class Node {
        let index: UnitModel.Pieces.Index
        let name: String
        let detail: String
        let scripts: String
        let children: [Node]

        init(index: UnitModel.Pieces.Index, model: UnitModel, refs: [UnitModel.Pieces.Index: String]) {
            self.index = index
            let piece = model.pieces[index]
            self.name = piece.name.isEmpty ? "(unnamed)" : piece.name
            let vertexCount = piece.primitives.reduce(0) { $0 + model.primitives[$1].indices.count }
            self.detail = "\(piece.primitives.count) / \(vertexCount) / \(piece.children.count)"
            self.scripts = refs[index] ?? ""
            self.children = piece.children.map { Node(index: $0, model: model, refs: refs) }
        }
    }
}

extension PieceHierarchyView: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? Node { return node.children.count }
        return nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node { return node.children[index] }
        return nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.children.isEmpty == false
    }
}

extension PieceHierarchyView: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node, let column = tableColumn else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("PieceCell.\(column.identifier.rawValue)")
        let cell: NSTableCellView
        if let existing = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.font = NSFont.systemFont(ofSize: 11)
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let value: String
        switch column {
        case nameColumn: value = node.name
        case detailColumn: value = node.detail
        case scriptsColumn: value = node.scripts
        default: value = ""
        }
        cell.textField?.stringValue = value
        cell.textField?.toolTip = column === scriptsColumn && !node.scripts.isEmpty ? node.scripts : nil
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selected = outline.item(atRow: outline.selectedRow) as? Node
        selectionDelegate?.pieceHierarchyView(self, didSelectPieceAt: selected?.index)
    }
}
