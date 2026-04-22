//
//  AppDelegate.swift
//  TAassets
//
//  Created by Logan Jones on 1/15/17.
//  Copyright © 2017 Logan Jones. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let modsMenu = NSMenu(title: "Mods")

    override init() {
        super.init()
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        let _ = TaassetsDocumentController.shared
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let item = NSMenuItem(title: "Mods", action: nil, keyEquivalent: "")
        modsMenu.delegate = self
        modsMenu.autoenablesItems = false
        item.submenu = modsMenu
        if let mainMenu = NSApp.mainMenu {
            let insertIndex = max(0, mainMenu.items.count - 1)
            mainMenu.insertItem(item, at: insertIndex)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

}

extension AppDelegate: NSMenuDelegate {

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === modsMenu else { return }
        menu.removeAllItems()

        guard let document = NSDocumentController.shared.currentDocument as? TaassetsDocument else {
            let placeholder = NSMenuItem(title: "No open TA document", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            return
        }

        let baseName = document.baseURL?.lastPathComponent ?? "Base"
        let baseTitle = "Base only: \(baseName)"
        let baseItem = NSMenuItem(title: baseTitle,
                                  action: #selector(activateModFromMenu(_:)),
                                  keyEquivalent: "")
        baseItem.target = self
        baseItem.representedObject = nil
        baseItem.state = (document.currentModURL == nil) ? .on : .off
        menu.addItem(baseItem)

        let mods = document.availableMods
        if mods.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let none = NSMenuItem(title: "No mods found in \(baseName)/mods",
                                  action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        menu.addItem(NSMenuItem.separator())
        for modURL in mods {
            let item = NSMenuItem(title: modURL.lastPathComponent,
                                  action: #selector(activateModFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = modURL
            item.state = (document.currentModURL == modURL) ? .on : .off
            menu.addItem(item)
        }
    }

    @IBAction func activateModFromMenu(_ sender: NSMenuItem) {
        Swift.print(">>> activateModFromMenu delegate fired; represented=\((sender.representedObject as? URL)?.lastPathComponent ?? "base only")")
        guard let doc = NSDocumentController.shared.currentDocument as? TaassetsDocument else {
            Swift.print("    no current TaassetsDocument")
            return
        }
        doc.activateMod(sender)
    }

}

