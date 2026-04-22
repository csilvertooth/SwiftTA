//
//  Document.swift
//  TAassets
//
//  Created by Logan Jones on 1/15/17.
//  Copyright © 2017 Logan Jones. All rights reserved.
//

import Cocoa
import SwiftTA_Core

class TaassetsDocument: NSDocument {

    var filesystem: FileSystem!
    var sides: [SideInfo] = []
    private(set) var baseURL: URL!
    private(set) var currentModURL: URL?

    var availableMods: [URL] {
        guard let baseURL = baseURL else { return [] }
        let modsDir = baseURL.appendingPathComponent("mods", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
                at: modsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        let allowed = Set(FileSystem.weightedArchiveExtensions)
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { dir in
                ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                    .contains { allowed.contains(($0 as NSString).pathExtension.lowercased()) }
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        let windowController = storyboard.instantiateController(withIdentifier: "Document Window Controller") as! NSWindowController
        let viewController = windowController.contentViewController as! TaassetsViewController
        viewController.shared = TaassetsSharedState(filesystem: filesystem, sides: sides)
        self.addWindowController(windowController)
    }

    override func read(from directoryURL: URL, ofType typeName: String) throws {

        let fm = FileManager.default
        var dirCheck: ObjCBool = false
        guard directoryURL.isFileURL, fm.fileExists(atPath: directoryURL.path, isDirectory: &dirCheck), dirCheck.boolValue
            else { throw NSError(domain: NSOSStatusErrorDomain, code: readErr, userInfo: nil) }

        let parent = directoryURL.deletingLastPathComponent()
        let parentName = parent.lastPathComponent.lowercased()
        if (parentName == "mods" || parentName == "mod"),
           TaassetsDocument.folderHasArchives(parent.deletingLastPathComponent()) {
            let grandparent = parent.deletingLastPathComponent()
            Swift.print("Detected mod folder \(directoryURL.lastPathComponent) under base \(grandparent.lastPathComponent); loading combined")
            baseURL = grandparent
            currentModURL = directoryURL
        } else {
            baseURL = directoryURL
            currentModURL = nil
        }
        try loadFilesystem()
    }

    private static func folderHasArchives(_ url: URL) -> Bool {
        let allowed = Set(FileSystem.weightedArchiveExtensions)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.contains { allowed.contains(($0 as NSString).pathExtension.lowercased()) }
    }

    private func loadFilesystem() throws {
        let begin = Date()
        filesystem = try FileSystem(mergingHpisIn: baseURL, modDirectory: currentModURL)
        let end = Date()
        let label = currentModURL.map { "\(baseURL.lastPathComponent) + mod:\($0.lastPathComponent)" } ?? baseURL.lastPathComponent
        Swift.print("\(label) filesystem load time: \(end.timeIntervalSince(begin)) seconds")

        if let sidedata = try? filesystem.openFile(at: "gamedata/sidedata.tdf"),
           let loaded = try? SideInfo.load(contentsOf: sidedata) {
            sides = loaded
        } else {
            sides = []
            Swift.print("No gamedata/sidedata.tdf found — palettes will fall back to PALETTE.PAL")
        }
    }

    @IBAction func activateMod(_ sender: NSMenuItem) {
        let newMod = sender.representedObject as? URL
        Swift.print(">>> activateMod invoked: \(newMod?.lastPathComponent ?? "base only")")
        guard newMod != currentModURL else {
            Swift.print("    same as current; skipping reload")
            return
        }
        let previous = currentModURL
        currentModURL = newMod
        do {
            try loadFilesystem()
            var controllersUpdated = 0
            for wc in windowControllers {
                if let vc = wc.contentViewController as? TaassetsViewController {
                    vc.shared = TaassetsSharedState(filesystem: filesystem, sides: sides)
                    vc.reloadCurrentContent()
                    controllersUpdated += 1
                }
            }
            Swift.print("    reloaded \(controllersUpdated) view controller(s)")
        } catch {
            Swift.print("    load failed: \(error) — reverting to \(previous?.lastPathComponent ?? "base")")
            currentModURL = previous
            NSAlert(error: error).runModal()
        }
    }

}

class TaassetsDocumentController: NSDocumentController {
    
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK else { return }
            guard let selectedURL = panel.urls.first else { return }
            self.openDocument(withContentsOf: selectedURL, display: true) { (document, wasOpened, error) in
                if let document = document {
                    print("opened document: \(document)")
                }
                else if let error = error {
                    print("error opening document: \(error)")
                }
            }
        }
    }
    
}


// MARK: - View

struct TaassetsSharedState {
    unowned let filesystem: FileSystem
    let sides: [SideInfo]
}
extension TaassetsSharedState {
    static var empty: TaassetsSharedState {
        return TaassetsSharedState(filesystem: FileSystem(), sides: [])
    }
}

class TaassetsViewController: NSViewController {
    
    var shared: TaassetsSharedState!
    
    @IBOutlet var unitsButton: NSButton!
    @IBOutlet var weaponsButton: NSButton!
    @IBOutlet var mapsButton: NSButton!
    @IBOutlet var filesButton: NSButton!
    @IBOutlet var contentView: NSView!
    
    private var selectedViewController: ContentViewController?
    private var selectedButton: NSButton?
    
    override func viewWillAppear() {
        super.viewWillAppear()

        applySidebarIcons()
        applySidebarSpacing()

        // There will be nothing selected the first time this view appears.
        // Select a default in this case.
        if selectedButton == nil {
            unitsButton.state = .on
            didChangeSelection(unitsButton)
        }
    }

    private func applySidebarSpacing() {
        if let stack = unitsButton.superview as? NSStackView {
            stack.edgeInsets = NSEdgeInsets(top: 28, left: 0, bottom: 8, right: 0)
        }
    }

    private func applySidebarIcons() {
        guard #available(macOS 11.0, *) else { return }
        let entries: [(NSButton, String, String)] = [
            (unitsButton,   "cube.fill",       "Units"),
            (weaponsButton, "scope",           "Weapons"),
            (mapsButton,    "map.fill",        "Maps"),
            (filesButton,   "folder.fill",     "Files"),
        ]
        for (button, symbol, label) in entries {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageAbove
                button.imageScaling = .scaleProportionallyDown
            }
        }
    }
    
    @IBAction func didChangeSelection(_ sender: NSButton) {

        // Disallow deselcetion (toggling).
        // A selected button can only be deselected by selecting something else.
        guard sender.state == .on, !(sender === selectedButton) else {
            sender.state = .on
            return
        }

        selectedButton?.state = .off
        selectedButton = sender
        showSelectedContent(for: sender)
    }

    func reloadCurrentContent() {
        Swift.print("    reloadCurrentContent called; selectedButton=\(String(describing: selectedButton?.identifier?.rawValue))")
        if let button = selectedButton {
            showSelectedContent(for: button)
        }
    }
    
    func showSelectedContent(for button: NSButton) {
        switch button {
        case unitsButton:
            showSelectedContent(controller: UnitBrowserViewController())
        case weaponsButton:
            showSelectedContent(controller: WeaponsBrowserViewController())
        case mapsButton:
            showSelectedContent(controller: MapBrowserViewController())
        case filesButton:
            showSelectedContent(controller: FileBrowserViewController())
        default:
            print("Unknown content button: \(button)")
        }
    }
    
    func showSelectedContent<T: ContentViewController>(controller: T) {
        selectedViewController?.view.removeFromSuperview()
        
        controller.shared = shared
        controller.view.frame = contentView.bounds
        controller.view.autoresizingMask = [.width, .height]
        contentView.addSubview(controller.view)
        selectedViewController = controller
    }
    
}

protocol ContentViewController: class {
    var view: NSView { get }
    var shared: TaassetsSharedState { get set }
}

class EmptyContentViewController: NSViewController, ContentViewController {
    
    var shared = TaassetsSharedState.empty
    
    override func loadView() {
        let mainView = NSView()
        
        let label = NSTextField(labelWithString: "Empty")
        label.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: mainView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: mainView.centerYAnchor),
            ])
        
        self.view = mainView
    }
    
}
