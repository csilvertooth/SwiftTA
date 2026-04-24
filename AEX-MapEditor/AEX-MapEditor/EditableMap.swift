//
//  EditableMap.swift
//  AEX-MapEditor
//
//  In-memory mutable wrapper around a TaMapModel. The UI layer holds
//  one of these per open document, applies commands to it, and serializes
//  back to disk via TaMapModel.writeTnt() on save.
//

import Foundation
import SwiftTA_Core


final class EditableMap {

    /// The original URL the map was loaded from. Subsequent saves go here
    /// unless the user explicitly chooses Save As.
    var fileURL: URL

    /// Current in-memory state of the map, including any pending edits.
    var model: TaMapModel

    /// Optional companion OTA file parsed as a TDF object graph. When
    /// present, Save writes this back alongside the .tnt. Currently only
    /// loaded for round-trip preservation; Phase 5 adds a form editor.
    var ota: [String: TdfParser.Object]?
    var otaURL: URL?

    /// Becomes true the moment the first edit lands; back to false after a
    /// successful save. The UI mirrors this in the window title.
    private(set) var isModified: Bool = false

    init(loadingFrom url: URL) throws {
        self.fileURL = url

        let bytes = try Data(contentsOf: url)
        let reader = MemoryFileHandle(data: bytes, name: url.lastPathComponent)
        let model = try MapModel(contentsOf: reader)
        switch model {
        case .ta(let ta):
            self.model = ta
        case .tak:
            throw EditableMapError.takNotYetSupported
        }

        // Look for a same-basename .ota sibling. Lowercased extension check
        // so macOS case-preservation quirks don't skip matching sidecars.
        let candidateOTA = url.deletingPathExtension().appendingPathExtension("ota")
        if FileManager.default.fileExists(atPath: candidateOTA.path),
           let otaBytes = try? Data(contentsOf: candidateOTA) {
            self.ota = TdfParser.extractAll(from: otaBytes)
            self.otaURL = candidateOTA
        }
    }

    func markModified() {
        isModified = true
    }

    func saveToCurrentLocation() throws {
        try save(to: fileURL, otaTo: otaURL)
    }

    func save(to tntURL: URL, otaTo explicitOtaURL: URL?) throws {
        let tntBytes = try model.writeTnt()
        try writeAtomic(tntBytes, to: tntURL, createBackup: true)

        if let ota = ota {
            let otaTarget = explicitOtaURL ?? tntURL.deletingPathExtension().appendingPathExtension("ota")
            let otaText = ota.serializeAsTdf()
            try writeAtomic(Data(otaText.utf8), to: otaTarget, createBackup: true)
            self.otaURL = otaTarget
        }

        self.fileURL = tntURL
        self.isModified = false
    }

    /// Write-with-backup: on first write to a location that already has a
    /// file, rename the original to `<name>.bak` before overwriting. Never
    /// overwrites an existing `.bak` to avoid clobbering a user's existing
    /// backup history.
    private func writeAtomic(_ data: Data, to url: URL, createBackup: Bool) throws {
        let fm = FileManager.default
        if createBackup && fm.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            if !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: url, to: backup)
            }
        }
        try data.write(to: url, options: [.atomic])
    }
}


enum EditableMapError: Error, LocalizedError {
    case takNotYetSupported

    var errorDescription: String? {
        switch self {
        case .takNotYetSupported:
            return "Total Annihilation: Kingdoms (.tnt v2) maps aren't editable yet — only the TA format is supported in this build."
        }
    }
}


// MARK: - Minimal in-memory FileReadHandle

/// Disk-backed reads go through FileHandle, which doesn't have a ready-
/// made FileReadHandle conformance we can reach from outside the core
/// package. An in-memory adapter is simpler and lets us load once, pass
/// the bytes around, and avoid holding an OS file handle open for the
/// editor's lifetime.
private final class MemoryFileHandle: FileReadHandle {
    private let data: Data
    private var cursor: Int = 0
    let fileName: String

    init(data: Data, name: String) {
        self.data = data
        self.fileName = name
    }

    var fileSize: Int { data.count }
    var fileOffset: Int { cursor }

    func seek(toFileOffset offset: Int) {
        cursor = max(0, min(offset, data.count))
    }

    func readData(ofLength length: Int) -> Data {
        let end = min(cursor + length, data.count)
        let slice = data.subdata(in: cursor..<end)
        cursor = end
        return slice
    }

    func readDataToEndOfFile() -> Data {
        let slice = data.subdata(in: cursor..<data.count)
        cursor = data.count
        return slice
    }
}
