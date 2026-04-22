//
//  WeaponsBrowser.swift
//  TAassets
//

import Cocoa
import SwiftTA_Core

struct WeaponInfo {
    let key: String
    let sourceFile: String
    let name: String
    let weaponType: String
    let range: Int
    let damage: [String: Int]
    let properties: [String: String]
}

class WeaponsBrowserViewController: NSViewController, ContentViewController {

    var shared = TaassetsSharedState.empty
    private var allWeapons: [WeaponInfo] = []
    private var weapons: [WeaponInfo] = []
    private var searchTerm: String = ""

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var detailText: NSTextView!

    override func loadView() {
        let bounds = NSRect(x: 0, y: 0, width: 720, height: 480)
        let mainView = NSView(frame: bounds)

        let listWidth: CGFloat = 280
        let searchHeight: CGFloat = 28

        let searchField = NSSearchField(frame: NSMakeRect(4, bounds.size.height - searchHeight - 2, listWidth - 8, searchHeight - 4))
        searchField.autoresizingMask = [.minYMargin]
        searchField.placeholderString = "Filter weapons"
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        mainView.addSubview(searchField)

        let scrollView = NSScrollView(frame: NSMakeRect(0, 0, listWidth, bounds.size.height - searchHeight))
        scrollView.autoresizingMask = [.height]
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let tableView = NSTableView(frame: NSMakeRect(0, 0, listWidth, bounds.size.height - searchHeight))
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Weapon"
        nameCol.width = listWidth - 100
        let rangeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("range"))
        rangeCol.title = "Range"
        rangeCol.width = 80
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(rangeCol)
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        mainView.addSubview(scrollView)

        let detailScroll = NSScrollView(frame: NSMakeRect(listWidth, 0, bounds.size.width - listWidth, bounds.size.height))
        detailScroll.autoresizingMask = [.width, .height]
        detailScroll.borderType = .noBorder
        detailScroll.hasVerticalScroller = true

        let textContainer = NSTextContainer(size: NSSize(width: bounds.size.width - listWidth, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        let detailText = NSTextView(frame: NSMakeRect(0, 0, bounds.size.width - listWidth, bounds.size.height), textContainer: textContainer)
        detailText.autoresizingMask = [.width]
        detailText.isEditable = false
        detailText.isRichText = false
        if #available(macOS 10.15, *) {
            detailText.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        } else {
            detailText.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
        }
        detailText.textColor = NSColor.labelColor
        detailText.backgroundColor = NSColor.textBackgroundColor
        detailText.textContainerInset = NSSize(width: 8, height: 8)
        detailScroll.documentView = detailText
        mainView.addSubview(detailScroll)

        self.view = mainView
        self.tableView = tableView
        self.searchField = searchField
        self.detailText = detailText
    }

    override func viewDidLoad() {
        let begin = Date()

        // Gather every top-level directory whose name starts with "weapon"
        // (weapons, weaponE, weaponsE, etc.) to cover mod layouts.
        let weaponDirs: [FileSystem.Directory] = shared.filesystem.root.items.compactMap { item in
            guard case .directory(let d) = item,
                  d.name.lowercased().hasPrefix("weapon") else { return nil }
            return d
        }

        let tdfFiles = weaponDirs.flatMap { $0.allFiles(withExtension: "tdf") }
        if weaponDirs.isEmpty {
            print("Weapons: no weapon directories found in filesystem root")
        } else {
            print("Weapons: scanning \(weaponDirs.map { $0.name }.joined(separator: ", ")) (\(tdfFiles.count) TDFs)")
        }

        var all: [WeaponInfo] = []
        var seen = Set<String>()
        for file in tdfFiles {
            guard let handle = try? shared.filesystem.openFile(file) else { continue }
            let parser = TdfParser(handle)
            let root = parser.extractObject(normalizeKeys: true)
            WeaponsBrowserViewController.collectWeapons(from: root, sourceFile: file.name, into: &all, seen: &seen)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.allWeapons = all
        self.weapons = all
        let end = Date()
        print("Weapons list load time: \(end.timeIntervalSince(begin)) seconds; weapons found: \(all.count) from \(tdfFiles.count) TDFs across \(weaponDirs.count) dir(s)")
    }

    /// Walks a parsed TDF tree looking for blocks that look like weapon definitions.
    /// A block is treated as a weapon if it has any of the hallmark properties
    /// (`weapontype`, `range`, `weaponvelocity`, `name` alongside damage data, etc.)
    /// or if it contains a `damage` subobject. Otherwise the walker descends into
    /// nested subobjects so container blocks like `[WEAPONDEFS]` don't hide content.
    private static func collectWeapons(from object: TdfParser.Object,
                                        sourceFile: String,
                                        into results: inout [WeaponInfo],
                                        seen: inout Set<String>) {
        for (key, sub) in object.subobjects {
            let lowerKey = key.lowercased()
            if looksLikeWeapon(sub) {
                guard seen.insert(lowerKey).inserted else { continue }
                results.append(WeaponInfo(from: sub, key: key, sourceFile: sourceFile))
            } else if !sub.subobjects.isEmpty {
                collectWeapons(from: sub, sourceFile: sourceFile, into: &results, seen: &seen)
            }
        }
    }

    private static func looksLikeWeapon(_ object: TdfParser.Object) -> Bool {
        let weaponishKeys: Set<String> = [
            "weapontype", "range", "weaponvelocity", "weaponlaserdef",
            "reloadtime", "accuracy", "areaofeffect", "energypershot",
            "metalpershot", "explosiongaf", "startvelocity", "lineofsight"
        ]
        for key in object.properties.keys where weaponishKeys.contains(key.lowercased()) {
            return true
        }
        if object.subobjects.keys.contains(where: { $0.lowercased() == "damage" }) {
            return true
        }
        return false
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        searchTerm = sender.stringValue.trimmingCharacters(in: .whitespaces)
        applyFilter()
    }

    private func applyFilter() {
        if searchTerm.isEmpty {
            weapons = allWeapons
        } else {
            let term = searchTerm.lowercased()
            weapons = allWeapons.filter {
                $0.key.lowercased().contains(term)
                    || $0.name.lowercased().contains(term)
                    || $0.weaponType.lowercased().contains(term)
                    || $0.sourceFile.lowercased().contains(term)
            }
        }
        tableView.reloadData()
        detailText.string = ""
    }
}

extension WeaponsBrowserViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { weapons.count }
}

extension WeaponsBrowserViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn else { return nil }
        let weapon = weapons[row]
        let id = NSUserInterfaceItemIdentifier("WeaponCell.\(column.identifier.rawValue)")
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingTail
            field.font = NSFont.systemFont(ofSize: 12)
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        switch column.identifier.rawValue {
        case "name": cell.textField?.stringValue = weapon.name.isEmpty ? weapon.key : weapon.name
        case "range": cell.textField?.stringValue = weapon.range > 0 ? "\(weapon.range)" : ""
        default: cell.textField?.stringValue = ""
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0, tableView.selectedRow < weapons.count else {
            detailText.string = ""
            return
        }
        let weapon = weapons[tableView.selectedRow]
        detailText.string = weapon.detailText()
    }
}

private extension WeaponInfo {

    init(from object: TdfParser.Object, key: String, sourceFile: String) {
        self.key = key
        self.sourceFile = sourceFile
        self.name = object.properties["name"] ?? key
        self.weaponType = object.properties["weapontype"] ?? ""
        self.range = Int(object.properties["range"] ?? "") ?? 0

        var damage: [String: Int] = [:]
        if let damages = object.subobjects["damage"] {
            for (armorClass, value) in damages.properties {
                if let v = Int(value) { damage[armorClass] = v }
            }
        }
        self.damage = damage
        self.properties = object.properties
    }

    func detailText() -> String {
        var lines: [String] = []
        lines.append(name)
        lines.append(String(repeating: "─", count: max(4, name.count)))
        lines.append("Key:           \(key)")
        lines.append("Source:        \(sourceFile)")
        if !weaponType.isEmpty { lines.append("Weapon type:   \(weaponType)") }
        if range > 0 { lines.append("Range:         \(range)") }

        if !damage.isEmpty {
            lines.append("")
            lines.append("Damage")
            for (armor, value) in damage.sorted(by: { $0.key < $1.key }) {
                lines.append(String(format: "  %-20@ %d", armor as NSString, value))
            }
        }

        lines.append("")
        lines.append("Properties")
        for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
            lines.append(String(format: "  %-20@ %@", key as NSString, value as NSString))
        }
        return lines.joined(separator: "\n")
    }
}
