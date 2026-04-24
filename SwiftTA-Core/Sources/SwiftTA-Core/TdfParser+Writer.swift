//
//  TdfParser+Writer.swift
//  SwiftTA-Core
//
//  Serializer for the Cavedog TDF container format used by .ota,
//  .tdf, .fbi, and related configuration files. Reader is in
//  TdfParser.swift.
//
//  The writer targets semantic — not byte-for-byte — round-trip
//  fidelity. TdfParser.Object stores properties and subobjects in
//  Swift Dictionaries, which are unordered. Serialization emits keys
//  in sorted order at each level for determinism, so the output will
//  generally not match an original author-formatted .ota byte-for-byte
//  but will parse back to the same object graph, which is what the
//  Cavedog engine and our own reader care about.
//
//  The map editor's strategy for OTA editing is: parse an OTA file
//  into a full TdfParser.Object tree (lossless, preserves every
//  field), mutate the specific fields the user is editing, then
//  serialize the whole tree back. That preserves mod-author or
//  mission-scripting fields we don't have structs for.
//

import Foundation


public extension TdfParser.Object {

    /// Serialize this object as a TDF-formatted named block:
    ///
    ///     [Name]
    ///     {
    ///         key=value;
    ///         [SubBlock]
    ///         { … }
    ///     }
    ///
    /// Properties are emitted before subobjects at each nesting
    /// level, and keys within a level are sorted alphabetically.
    ///
    /// - Parameters:
    ///   - name: the block name to open with. When nil, only the
    ///     contents are emitted (no surrounding `[Name]{…}`) — useful
    ///     when wrapping the whole tree yourself.
    ///   - indent: tab-depth of the outer block. Subobjects indent one
    ///     level deeper.
    func serializeAsTdf(name: String? = nil, indent: Int = 0) -> String {
        var out = ""
        let outerPad = String(repeating: "\t", count: indent)
        let innerIndent = (name != nil) ? indent + 1 : indent
        let innerPad = String(repeating: "\t", count: innerIndent)

        if let name = name {
            out.append("\(outerPad)[\(name)]\n")
            out.append("\(outerPad){\n")
        }

        for key in properties.keys.sorted() {
            let value = properties[key] ?? ""
            out.append("\(innerPad)\(key)=\(value);\n")
        }

        for subKey in subobjects.keys.sorted() {
            guard let subObject = subobjects[subKey] else { continue }
            out.append(subObject.serializeAsTdf(name: subKey, indent: innerIndent))
        }

        if name != nil {
            out.append("\(outerPad)}\n")
        }

        return out
    }
}


public extension Dictionary where Key == String, Value == TdfParser.Object {

    /// Serialize a top-level TDF document: every entry is written as a
    /// named block in sorted order. Matches the shape returned by
    /// `TdfParser.extractAll()`.
    func serializeAsTdf() -> String {
        var out = ""
        for name in keys.sorted() {
            guard let object = self[name] else { continue }
            out.append(object.serializeAsTdf(name: name, indent: 0))
        }
        return out
    }
}
