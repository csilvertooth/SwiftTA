//
//  ArchiveMapPicker.swift
//  AEX-MapEditor
//
//  TA ships maps inside .hpi / .ufo / .ccx / .gp3 / .gpf archives, so
//  the editor needs to: open an archive, enumerate the map files it
//  contains, let the user pick one, and extract the .tnt (plus .ota
//  sidecar if present) to a writable staging directory so the rest of
//  the editor can treat it as a normal loose map. Future phases can add
//  an "Export to…" flow that writes to a user-chosen folder; for MVP we
//  keep extracts in Application Support and let the user Save As out of
//  the editor when they want them somewhere else.
//

import Cocoa
import SwiftTA_Core


enum ArchiveMapPicker {

    struct MapEntry {
        /// Base name without extension — used as the map's display name.
        var name: String
        /// The file metadata for the .tnt entry in the archive.
        var tnt: HpiItem.File
        /// The companion .ota entry if present.
        var ota: HpiItem.File?
    }

    enum PickerError: LocalizedError {
        case noMapsInArchive(URL)
        case extractFailed(file: String, underlying: Error)
        case couldNotCreateStagingDirectory(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .noMapsInArchive(let url):
                return "\(url.lastPathComponent) doesn't contain any map files."
            case .extractFailed(let file, let underlying):
                return "Failed to extract \(file) — \(underlying.localizedDescription)"
            case .couldNotCreateStagingDirectory(let underlying):
                return "Couldn't create a staging directory for extracted maps — \(underlying.localizedDescription)"
            }
        }
    }

    /// Reads the archive, lists every .tnt entry, pairs each with its
    /// same-basename .ota sidecar when present, and returns the result
    /// sorted by map name.
    static func listMaps(in archiveURL: URL) throws -> [MapEntry] {
        let root = try HpiItem.loadFromArchive(contentsOf: archiveURL)

        var tntsByBase: [String: HpiItem.File] = [:]
        var otasByBase: [String: HpiItem.File] = [:]

        walk(directory: root) { file in
            let lowered = file.name.lowercased()
            let base = (file.name as NSString).deletingPathExtension.lowercased()
            if lowered.hasSuffix(".tnt") {
                // First wins on collisions. Archive writers typically keep
                // one definitive entry per name; if two ever collide, the
                // user sees whichever appears first in the walk.
                if tntsByBase[base] == nil { tntsByBase[base] = file }
            } else if lowered.hasSuffix(".ota") {
                if otasByBase[base] == nil { otasByBase[base] = file }
            }
        }

        var entries: [MapEntry] = []
        entries.reserveCapacity(tntsByBase.count)
        for (base, tnt) in tntsByBase {
            let displayName = (tnt.name as NSString).deletingPathExtension
            entries.append(MapEntry(name: displayName, tnt: tnt, ota: otasByBase[base]))
        }
        entries.sort { $0.name.lowercased() < $1.name.lowercased() }
        return entries
    }

    /// Extracts the given map (tnt + ota when available) from the
    /// archive into the staging directory and returns the URL of the
    /// on-disk .tnt the editor should open next.
    static func extract(_ entry: MapEntry, from archiveURL: URL) throws -> URL {
        let stagingDir = try ensureStagingDirectory(for: archiveURL)

        let tntBytes: Data
        do {
            tntBytes = try HpiItem.extract(file: entry.tnt, fromHPI: archiveURL)
        } catch {
            throw PickerError.extractFailed(file: entry.tnt.name, underlying: error)
        }

        let tntURL = stagingDir.appendingPathComponent(entry.name + ".tnt")
        try tntBytes.write(to: tntURL, options: [.atomic])

        if let ota = entry.ota {
            do {
                let otaBytes = try HpiItem.extract(file: ota, fromHPI: archiveURL)
                let otaURL = stagingDir.appendingPathComponent(entry.name + ".ota")
                try otaBytes.write(to: otaURL, options: [.atomic])
            } catch {
                // A bad OTA shouldn't block the TNT from opening — log
                // and continue. The editor will just treat the map as
                // having no metadata sidecar.
                NSLog("AEX-MapEditor: OTA extract failed for \(entry.name): \(error.localizedDescription)")
            }
        }

        return tntURL
    }

    /// Modal picker dialog: presents a popup of every map in the
    /// archive and returns the selection, or nil on cancel.
    static func presentPicker(for maps: [MapEntry], archiveName: String) -> MapEntry? {
        guard !maps.isEmpty else { return nil }

        let alert = NSAlert()
        alert.messageText = "Pick a map to edit"
        alert.informativeText = "\(archiveName) contains \(maps.count) map\(maps.count == 1 ? "" : "s")."

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26), pullsDown: false)
        for map in maps {
            popup.addItem(withTitle: map.name)
        }
        alert.accessoryView = popup

        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        guard maps.indices.contains(index) else { return nil }
        return maps[index]
    }

    // MARK: - Internals

    private static func walk(directory: HpiItem.Directory, visit: (HpiItem.File) -> Void) {
        for item in directory.items {
            switch item {
            case .file(let file): visit(file)
            case .directory(let sub): walk(directory: sub, visit: visit)
            }
        }
    }

    private static func ensureStagingDirectory(for archiveURL: URL) throws -> URL {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let archiveStem = archiveURL.deletingPathExtension().lastPathComponent
        let stagingDir = support
            .appendingPathComponent("AEX-MapEditor", isDirectory: true)
            .appendingPathComponent("Extracted", isDirectory: true)
            .appendingPathComponent(archiveStem, isDirectory: true)

        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw PickerError.couldNotCreateStagingDirectory(underlying: error)
        }
        return stagingDir
    }
}
