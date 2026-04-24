//
//  AppDelegate.swift
//  AEX-MapEditor
//
//  Minimal AppKit bootstrapping. The editor is a single-window, non-
//  document-based app: File → Open picks a .tnt, we spawn one window.
//  Multiple open maps live as multiple windows, each with its own
//  MapEditorWindowController and its own EditableMap.
//

import Cocoa
import SwiftTA_Core


class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [MapEditorWindowController] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // applicationWillFinishLaunching is the canonical spot to install a
        // programmatic menu bar — AppKit reads NSApp.mainMenu once during
        // the rest of startup, so setting it here is guaranteed to be
        // picked up before the menu bar renders.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        NSLog("AEX-MapEditor: installed mainMenu with \(NSApp.mainMenu?.items.count ?? 0) top-level items")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Installs a minimal menu bar programmatically rather than via a
    /// MainMenu.xib. Keeps the app self-contained and avoids the
    /// maintenance burden of a NIB for the six items we actually use.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu (Apple-style per-app menu: About, Hide, Quit).
        // macOS takes the first top-level item's title from the process
        // name regardless of what we set, but every other top-level item
        // inherits its label from NSMenuItem.title — so the File / Edit /
        // Window items below each need their own explicit title.
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About AEX Map Editor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide AEX Map Editor", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit AEX Map Editor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu.
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "Save As…", action: #selector(saveDocumentAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]

        // Edit menu (undo + redo; rest can go on later).
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(undo(_:)), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(redo(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        // Window menu.
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returning true unconditionally makes the app quit the moment
        // any window closes — including the File → Open panel when the
        // user cancels it, which leaves nothing else on screen. Only
        // terminate once a map window has actually been opened and all
        // map windows are now closed. A freshly-launched app with no map
        // opened yet (or one whose user cancelled the open panel) stays
        // running and reachable from the menu bar / Dock.
        return everOpenedAMap && windowControllers.isEmpty
    }

    /// Flipped to true the first time `openMap(at:)` successfully shows a
    /// window. Never flips back, so the last-map-closed shutdown rule
    /// kicks in from then on.
    private var everOpenedAMap = false

    @IBAction func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["tnt", "hpi", "ufo", "ccx", "gp3", "gpf"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Pick a loose .tnt, or an archive (.hpi / .ufo / .ccx / .gp3 / .gpf) to browse the maps inside."

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openFromFilePicker(url)
        }
    }

    private func openFromFilePicker(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "tnt" {
            openMap(at: url)
        } else {
            openMapFromArchive(url)
        }
    }

    private func openMapFromArchive(_ archiveURL: URL) {
        let maps: [ArchiveMapPicker.MapEntry]
        do {
            maps = try ArchiveMapPicker.listMaps(in: archiveURL)
        } catch {
            presentError(error, contextMessage: "Couldn't read \(archiveURL.lastPathComponent)")
            return
        }

        if maps.isEmpty {
            presentError(ArchiveMapPicker.PickerError.noMapsInArchive(archiveURL),
                         contextMessage: "No maps found")
            return
        }

        guard let choice = ArchiveMapPicker.presentPicker(for: maps, archiveName: archiveURL.lastPathComponent) else {
            return
        }

        let extractedURL: URL
        do {
            extractedURL = try ArchiveMapPicker.extract(choice, from: archiveURL)
        } catch {
            presentError(error, contextMessage: "Couldn't extract \(choice.name) from \(archiveURL.lastPathComponent)")
            return
        }

        openMap(at: extractedURL)
    }

    func openMap(at url: URL) {
        do {
            let controller = try MapEditorWindowController(mapURL: url)
            windowControllers.append(controller)
            controller.showWindow(nil)
            everOpenedAMap = true
            NSDocumentController.shared.noteNewRecentDocumentURL(url)

            // Drop the controller from our retain set when its window closes
            // so a long-running session doesn't leak every opened map.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: controller.window,
                queue: .main
            ) { [weak self, weak controller] _ in
                guard let self, let controller else { return }
                self.windowControllers.removeAll { $0 === controller }
            }
        } catch {
            presentError(error, contextMessage: "Couldn't open \(url.lastPathComponent)")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            openMap(at: url)
        }
    }

    // MARK: - File menu

    @IBAction func saveDocument(_ sender: Any?) {
        frontmostController()?.saveMap()
    }

    @IBAction func saveDocumentAs(_ sender: Any?) {
        frontmostController()?.saveMapAs()
    }

    @IBAction func undo(_ sender: Any?) {
        frontmostController()?.undoLastEdit()
    }

    @IBAction func redo(_ sender: Any?) {
        frontmostController()?.redoLastEdit()
    }

    private func frontmostController() -> MapEditorWindowController? {
        if let window = NSApp.keyWindow,
           let controller = window.windowController as? MapEditorWindowController {
            return controller
        }
        return windowControllers.last
    }

    // MARK: - Error presentation

    private func presentError(_ error: Error, contextMessage: String) {
        let alert = NSAlert()
        alert.messageText = contextMessage
        alert.informativeText = (error as NSError).localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
