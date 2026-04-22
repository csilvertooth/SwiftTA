//
//  UnitScript+PieceReferences.swift
//  SwiftTA-Core
//

import Foundation

public extension UnitScript {

    /// A reference to a model piece emitted by a COB instruction.
    struct PieceReference: Hashable {
        public let moduleName: String
        public let opcode: UnitScript.Opcode
    }

    /// Maps each script-piece-index to the set of instructions across all modules that touch that piece.
    ///
    /// The index is into `UnitScript.pieces`. Resolve piece names via `pieces[index]`, then match
    /// against `UnitModel.nameLookup` (case-insensitive) to locate the model piece.
    func pieceReferences() -> [Int: [PieceReference]] {
        var result: [Int: [PieceReference]] = [:]
        let moduleEnds = sortedModuleEnds()

        for (moduleIndex, module) in modules.enumerated() {
            let end = moduleEnds[moduleIndex]
            var ip = module.offset
            while ip < end {
                guard let opcode = UnitScript.Opcode(rawValue: code[ip]) else {
                    ip += 1
                    continue
                }
                let layout = UnitScript.operandLayout(for: opcode)
                if let pieceOffset = layout.pieceOperandOffset, ip + pieceOffset < code.count {
                    let pieceIdx = Int(code[ip + pieceOffset])
                    if pieces.indices.contains(pieceIdx) {
                        result[pieceIdx, default: []].append(
                            PieceReference(moduleName: module.name, opcode: opcode))
                    }
                }
                ip += layout.totalLength
                if opcode == .`return` { break }
            }
        }
        return result
    }

    private func sortedModuleEnds() -> [Code.Index] {
        let starts = modules.map { $0.offset }
        let sortedStarts = starts.sorted()
        var ends = Array(repeating: code.count, count: modules.count)
        for (i, start) in modules.enumerated() {
            if let next = sortedStarts.first(where: { $0 > start.offset }) {
                ends[i] = next
            }
        }
        return ends
    }

    /// Per-opcode operand layout: the length of the opcode + its trailing immediate operands in the code stream,
    /// and where (if anywhere) the piece-index operand sits relative to the opcode.
    static func operandLayout(for opcode: UnitScript.Opcode) -> (totalLength: Int, pieceOperandOffset: Int?) {
        switch opcode {
        case .movePieceWithSpeed, .turnPieceWithSpeed,
             .startSpin, .stopSpin,
             .movePieceNow, .turnPieceNow,
             .waitForTurn, .waitForMove,
             .explode:
            return (3, 1)
        case .showPiece, .hidePiece,
             .cachePiece, .dontCachePiece,
             .dontShadow, .dontShade,
             .emitSfx:
            return (2, 1)
        case .pushImmediate, .pushLocal, .pushStatic,
             .setLocal, .setStatic,
             .jumpToOffset, .jumpToOffsetIfFalse,
             .playSound, .setSignalMask:
            return (2, nil)
        case .startScript, .callScript:
            return (3, nil)
        case .stackAllocate, .popStack, .sleep,
             .add, .subtract, .multiply, .divide,
             .bitwiseAnd, .bitwiseOr,
             .unknown1, .unknown2, .unknown3,
             .random,
             .getUnitValue, .getFunctionResult,
             .lessThan, .lessThanOrEqual,
             .greaterThan, .greaterThanOrEqual,
             .equal, .notEqual,
             .and, .or, .not,
             .`return`, .signal,
             .mapCommand, .setUnitValue,
             .attachUnit, .dropUnit:
            return (1, nil)
        }
    }
}
