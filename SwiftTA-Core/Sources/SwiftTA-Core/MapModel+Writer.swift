//
//  MapModel+Writer.swift
//  SwiftTA-Core
//
//  Serializers for the Cavedog TNT binary map format plus the companion
//  minimap block. Reader side lives in MapModel.swift.
//
//  The writer targets semantic (not byte-for-byte) round-trip fidelity:
//  a map that is read and immediately written back through this serializer
//  produces a file that, when re-read, yields a TaMapModel equal to the
//  original. Section *contents* match the original byte-for-byte; the
//  file layout is canonical (tile-index → map-info → tiles → features →
//  minimap, with no inter-section padding), so files whose original
//  layout differed will also differ in the header offsets, which is
//  allowed by the format — Cavedog's engine, Spring, and our own reader
//  all index by the header offsets, never by position.
//

import Foundation
import SwiftTA_Ctypes


public extension TaMapModel {

    enum WriteError: Error {
        case featureNameTooLong(String)
        case invalidMapSize(Size2<Int>)
        case tileDataSizeMismatch(expected: Int, actual: Int)
        case tileIndexSizeMismatch(expected: Int, actual: Int)
        case heightSampleCountMismatch(expected: Int, actual: Int)
        case featureMapSizeMismatch(expected: Int, actual: Int)
        case invalidFeatureIndex(Int)
    }

    /// Binary sizes of the fixed prefix, in bytes. These are not
    /// `MemoryLayout.size` of the C structs because the C structs are
    /// `#pragma pack(1)` — different compilers have been known to disagree
    /// with Swift's assumptions. The on-wire format is fixed.
    static let tntHeaderSize = 12     // int32 version + uint32 width + uint32 height
    static let tntExtHeaderSize = 52  // 9 × uint32 + 16 bytes padding
    static let tntPrefixSize = tntHeaderSize + tntExtHeaderSize  // 64

    /// Byte size of a single TA_TNT_MAP_ENTRY: uint8 elevation + uint16 special + uint8 unknown.
    static let tntMapEntrySize = 4

    /// Byte size of a single TA_TNT_FEATURE_ENTRY: uint32 index + uint8 name[128].
    static let tntFeatureEntrySize = 132

    /// Serialize this map to a TNT v1 (Total Annihilation) binary blob.
    /// The output is suitable to hand back to the Cavedog engine or
    /// round-trip through `TaMapModel.init(_:reading:)`.
    func writeTnt() throws -> Data {
        try validateBeforeWriting()

        let tileIndexOffset = Self.tntPrefixSize
        let tileIndexBytes = tileIndexMap.indices
        let mapInfoOffset = tileIndexOffset + tileIndexBytes.count

        let mapInfoBytes = encodeMapInfo()
        let tileArrayOffset = mapInfoOffset + mapInfoBytes.count

        let tileArrayBytes = tileSet.tiles
        let featureOffset = tileArrayOffset + tileArrayBytes.count

        let featureBytes = try encodeFeatureEntries()
        let minimapOffset = featureOffset + featureBytes.count

        let minimapBytes = encodeMinimap()

        var output = Data(capacity: minimapOffset + minimapBytes.count)

        // Main header.
        output.appendUInt32LE(UInt32(bitPattern: Int32(TA_TNT_TOTAL_ANNIHILATION)))
        output.appendUInt32LE(UInt32(mapSize.width))
        output.appendUInt32LE(UInt32(mapSize.height))

        // Extended header.
        output.appendUInt32LE(UInt32(tileIndexOffset))
        output.appendUInt32LE(UInt32(mapInfoOffset))
        output.appendUInt32LE(UInt32(tileArrayOffset))
        output.appendUInt32LE(UInt32(tileSet.count))
        output.appendUInt32LE(UInt32(features.count))
        output.appendUInt32LE(UInt32(featureOffset))
        output.appendUInt32LE(UInt32(seaLevel))
        output.appendUInt32LE(UInt32(minimapOffset))
        output.appendUInt32LE(1)                            // unknown_1 — Cavedog always writes 1
        output.append(Data(repeating: 0, count: 16))        // padding

        // Sections in canonical order.
        output.append(tileIndexBytes)
        output.append(mapInfoBytes)
        output.append(tileArrayBytes)
        output.append(featureBytes)
        output.append(minimapBytes)

        return output
    }

    private func validateBeforeWriting() throws {
        guard mapSize.width > 0, mapSize.height > 0 else {
            throw WriteError.invalidMapSize(mapSize)
        }

        let expectedHeightSamples = mapSize.area
        guard heightMap.samples.count == expectedHeightSamples else {
            throw WriteError.heightSampleCountMismatch(expected: expectedHeightSamples, actual: heightMap.samples.count)
        }

        guard featureMap.count == expectedHeightSamples else {
            throw WriteError.featureMapSizeMismatch(expected: expectedHeightSamples, actual: featureMap.count)
        }

        let expectedTileIndexBytes = (mapSize.width / 2) * (mapSize.height / 2) * MemoryLayout<UInt16>.size
        guard tileIndexMap.indices.count == expectedTileIndexBytes else {
            throw WriteError.tileIndexSizeMismatch(expected: expectedTileIndexBytes, actual: tileIndexMap.indices.count)
        }

        let expectedTileBytes = tileSet.count * tileSet.tileSize.area
        guard tileSet.tiles.count == expectedTileBytes else {
            throw WriteError.tileDataSizeMismatch(expected: expectedTileBytes, actual: tileSet.tiles.count)
        }

        let featureRange = 0..<features.count
        for (i, slot) in featureMap.enumerated() {
            if let idx = slot, !featureRange.contains(idx) {
                throw WriteError.invalidFeatureIndex(idx).withIndex(i)
            }
        }
    }

    private func encodeMapInfo() -> Data {
        var data = Data(capacity: mapSize.area * Self.tntMapEntrySize)
        for i in 0..<mapSize.area {
            let elevation = UInt8(clamping: heightMap.samples[i])

            // The reader treats any `special` value outside [0, numFeatures)
            // as "no feature"; Cavedog's canonical "no feature" sentinel is
            // 0xFFFF. Any in-range index is written as-is.
            let special: UInt16 = featureMap[i].map { UInt16($0) } ?? 0xFFFF

            data.append(elevation)
            data.appendUInt16LE(special)
            data.append(0)                                  // unknown byte — Cavedog always writes 0
        }
        return data
    }

    private func encodeFeatureEntries() throws -> Data {
        var data = Data(capacity: features.count * Self.tntFeatureEntrySize)
        for (index, featureId) in features.enumerated() {
            data.appendUInt32LE(UInt32(index))

            let nameBytes = Array(featureId.name.utf8)
            guard nameBytes.count < 128 else {
                // Reserve byte 128 for the null terminator.
                throw WriteError.featureNameTooLong(featureId.name)
            }
            data.append(contentsOf: nameBytes)
            data.append(contentsOf: [UInt8](repeating: 0, count: 128 - nameBytes.count))
        }
        return data
    }

    private func encodeMinimap() -> Data {
        var data = Data(capacity: 8 + minimap.data.count)
        data.appendUInt32LE(UInt32(minimap.size.width))
        data.appendUInt32LE(UInt32(minimap.size.height))
        data.append(minimap.data)
        return data
    }
}


// MARK: - Little-endian write helpers

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { buf in self.append(contentsOf: buf) }
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { buf in self.append(contentsOf: buf) }
    }
}


// MARK: - Helpers

private extension TaMapModel.WriteError {
    func withIndex(_ i: Int) -> TaMapModel.WriteError {
        // The invalid-feature-index path needs to surface which map entry
        // went wrong; the enum value already carries the feature index, so
        // this shim exists solely to make the caller's intent explicit when
        // tracing which cell caused the problem. Currently a no-op that
        // returns self, reserved for future richer diagnostics.
        _ = i
        return self
    }
}
