//
//  UnitScript+Instructions.swift
//  TAassets
//
//  Created by Logan Jones on 1/29/18.
//  Copyright © 2018 Logan Jones. All rights reserved.
//

import Foundation


struct ScriptExecutionContext {
    var process: UnitScript.Context
    var thread: UnitScript.Thread
    /// The instance is shared mutably across all threads within a single run()
    /// tick so that `turn piece now` / `move piece now` take effect immediately
    /// and later reads in the same script evaluation see the updated state.
    var model: UnsafeMutablePointer<UnitModel.Instance>
    var machine: ScriptMachine
}

private extension ScriptExecutionContext {
    
    func immediate(at offset: UnitScript.Code.Index) -> UnitScript.CodeUnit {
        return process.script.code[thread.instructionPointer + offset]
    }
    
}

/**
 Instruction execution function.
 An `Instruction` executes its instruction logic on the given `ScriptExecutionContext`.
 
 - Parameter execution: The current context in which to execute this instruction. The context is used to load immediate values, access & modify the stack, and more.
 - Throws: An instruction will throw a `ExecutionError` if it cannot decode and execute correctly.
 */
typealias Instruction = (ScriptExecutionContext) throws -> ()

/**
 A map of valid `Opcode` values to the `Instruction` functions that execute the instruction.
 */
let Instructions: [UnitScript.Opcode: Instruction] = [
    .movePieceWithSpeed: movePieceWithSpeed,
    .turnPieceWithSpeed: turnPieceWithSpeed,
    .startSpin: startSpin,
    .stopSpin: stopSpin,
    .showPiece: showPiece,
    .hidePiece: hidePiece,
    .cachePiece: cachePiece,
    .dontCachePiece: dontCachePiece,
    .dontShadow: dontShadow,
    .movePieceNow: movePieceNow,
    .turnPieceNow: turnPieceNow,
    .dontShade: dontShade,
    .emitSfx: emitSfx,
    .waitForTurn: waitForTurn,
    .waitForMove: waitForMove,
    .sleep: sleep,
    .pushImmediate: pushImmediate,
    .pushLocal: pushLocal,
    .pushStatic: pushStatic,
    .stackAllocate: stackAllocate,
    .setLocal: setLocal,
    .setStatic: setStatic,
    .popStack: popStack,
    .add: operatorFunc(operation: &+),
    .subtract: operatorFunc(operation: &-),
    .multiply: operatorFunc(operation: &*),
    .divide: operatorFunc(operation: { lhs, rhs in rhs == 0 ? 0 : lhs / rhs }),
    .bitwiseAnd: operatorFunc(operation: &),
    .bitwiseOr: operatorFunc(operation: |),
    .unknown1: unknownOperator,
    .unknown2: unknownOperator,
    .unknown3: unknownOperator,
    .random: operatorFunc(operation: taRandom),
    .getUnitValue: getUnitValue,
    .getFunctionResult: getFunctionResult,
    .lessThan: operatorFunc(comparison: <),
    .lessThanOrEqual: operatorFunc(comparison: <=),
    .greaterThan: operatorFunc(comparison: >),
    .greaterThanOrEqual: operatorFunc(comparison: >=),
    .equal: operatorFunc(comparison: ==),
    .notEqual: operatorFunc(comparison: !=),
    .and: operatorFunc(operation: _StackValue.booleanAnd),
    .or: operatorFunc(operation: _StackValue.booleanOr),
    .not: operatorFunc(modification: _StackValue.booleanNot),
    .startScript: startScript,
    .callScript: callScript,
    .jumpToOffset: jumpToOffset,
    .`return`: returnResult,
    .jumpToOffsetIfFalse: jumpToOffsetIfFalse,
    .signal: signal,
    .setSignalMask: setSignalMask,
    .explode: explode,
    .playSound: playSound,
    .mapCommand: mapCommand,
    .setUnitValue: setUnitValue,
    .attachUnit: attachUnit,
    .dropUnit: dropUnit,
]

/**
 
 Code
 * 0x10001000
 * piece index
 * axis index
 
 Stack
 * ← destination: linear
 * ← speed: linear
 
 */
private func movePieceWithSpeed(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let destination = try execution.thread.stack.pop()
    let speed = try execution.thread.stack.pop()
    
    let translation = execution.model.pointee.beginTranslation(
        for: try execution.process.pieceIndex(at: piece),
        along: try execution.thread.makeAxis(for: axis),
        to: destination.linearValue,
        with: speed.linearValue)
    execution.process.animations.append(translation)
    
    //print("[\(execution.thread.id)] Move \(piece) along \(axis) to \(destination) with speed \(speed)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10002000
 * piece index
 * axis index
 
 Stack
 * ← destination: angular
 * ← speed: angular
 
 */
private func turnPieceWithSpeed(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let destination = try execution.thread.stack.pop()
    let speed = try execution.thread.stack.pop()
    
    let rotation = execution.model.pointee.beginRotation(
        for: try execution.process.pieceIndex(at: piece),
        around: try execution.thread.makeAxis(for: axis),
        to: destination.angularValue,
        with: speed.angularValue)
    execution.process.animations.append(rotation)
    
    //print("[\(execution.thread.id)] Turn \(piece) around \(axis) to \(destination) with speed \(speed)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10003000
 * piece index
 * axis index
 
 Stack
 * ← speed: angular
 * ← acceleration: angular
 
 */
private func startSpin(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let speed = try execution.thread.stack.pop()
    let acceleration = try execution.thread.stack.pop()
    
    let spin = execution.model.pointee.beginSpin(
        for: try execution.process.pieceIndex(at: piece),
        around: try execution.thread.makeAxis(for: axis),
        accelerating: acceleration.angularValue,
        to: speed.angularValue)
    execution.process.animations.append(spin)
    
    //print("[\(execution.thread.id)] Spin \(piece) around \(axis) accelerate \(acceleration) to speed \(speed)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10004000
 * piece index
 * axis index
 
 Stack
 * ← decceleration: angular
 
 */
private func stopSpin(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let decceleration = try execution.thread.stack.pop()
    
    if let found = execution.process.findSpinAnimation(of: try execution.process.pieceIndex(at: piece), around: try execution.thread.makeAxis(for: axis)) {
        var spin = found.spin
        spin.acceleration = decceleration.angularValue * GameFloat.pi/180.0
        execution.process.animations[found.index] = .spinDown(spin)
    }
    
    //print("[\(execution.thread.id)] Stop spin \(piece) around \(axis) deccelerate \(decceleration)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10005000
 * piece index
 
 */
private func showPiece(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    
    execution.process.animations.append(.show(try execution.process.pieceIndex(at: piece)))
    
    //print("[\(execution.thread.id)] Show \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10006000
 * piece index
 
 */
private func hidePiece(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    
    execution.process.animations.append(.hide(try execution.process.pieceIndex(at: piece)))
    
    //print("[\(execution.thread.id)] Hide \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10007000
 * piece index
 
 */
private func cachePiece(execution: ScriptExecutionContext) throws {
    //print("[\(execution.thread.id)] Cache \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10008000
 * piece index
 
 */
private func dontCachePiece(execution: ScriptExecutionContext) throws {
    //print("[\(execution.thread.id)] Don't Cache \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x1000A000
 * piece index
 
 */
private func dontShadow(execution: ScriptExecutionContext) throws {
    //print("[\(execution.thread.id)] Don't Shadow \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x1000B000
 * piece index
 * axis index
 
 Stack
 * ← destination: linear
 
 */
private func movePieceNow(execution: ScriptExecutionContext) throws {

    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let destination = try execution.thread.stack.pop()

    let pieceIndex = try execution.process.pieceIndex(at: piece)
    let resolvedAxis = try execution.thread.makeAxis(for: axis)
    let target = destination.linearValue
    switch resolvedAxis {
    case .x: execution.model.pointee.pieces[pieceIndex].move.x = target
    case .y: execution.model.pointee.pieces[pieceIndex].move.y = target
    case .z: execution.model.pointee.pieces[pieceIndex].move.z = target
    }

    //print("[\(execution.thread.id)] Move \(piece) along \(axis) to \(destination)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x1000C000
 * piece index
 * axis index
 
 Stack
 * ← destination: angular
 
 */
private func turnPieceNow(execution: ScriptExecutionContext) throws {

    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    let destination = try execution.thread.stack.pop()

    let pieceIndex = try execution.process.pieceIndex(at: piece)
    let resolvedAxis = try execution.thread.makeAxis(for: axis)
    let target = destination.angularValue
    switch resolvedAxis {
    case .x: execution.model.pointee.pieces[pieceIndex].turn.x = target
    case .y: execution.model.pointee.pieces[pieceIndex].turn.y = target
    case .z: execution.model.pointee.pieces[pieceIndex].turn.z = target
    }

    //print("[\(execution.thread.id)] Turn \(piece) around \(axis) to \(destination)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x1000E000
 * piece index
 
 */
private func dontShade(execution: ScriptExecutionContext) throws {
    //print("[\(execution.thread.id)] Don't Shade \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x1000F000
 * piece index
 
 */
private func emitSfx(execution: ScriptExecutionContext) throws {
    //print("[\(execution.thread.id)] Emit SFX \(piece)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10011000
 * piece index
 * axis index
 
 */
private func waitForTurn(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    
    execution.thread.status = .waitingForTurn(Int(piece), try execution.thread.makeAxis(for: axis))
    
    print("[\(execution.thread.id)] wait for turn: \(piece) around \(axis)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10012000
 * piece index
 * axis index
 
 */
private func waitForMove(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let axis = execution.immediate(at: 2)
    
    execution.thread.status = .waitingForMove(Int(piece), try execution.thread.makeAxis(for: axis))
    
    print("[\(execution.thread.id)] wait for move: \(piece) along \(axis)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10013000
 
 Stack
 * ← duration: time
 
 */
private func sleep(execution: ScriptExecutionContext) throws {
    
    let duration = try execution.thread.stack.pop()
    let time = execution.machine.getTime()
    
    execution.thread.status = .sleeping(time + (Double(duration) / 1500.0))
    
    //print("[\(execution.thread.id)] sleep \(sleep) =~ \(GameFloat(sleep) / 1500)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10021001
 * value
 
 Stack
 * → value
 
 */
private func pushImmediate(execution: ScriptExecutionContext) throws {
    
    let value = execution.immediate(at: 1)
    execution.thread.stack.push(value)
    
    //print("[\(execution.thread.id)] push value \(value)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10021002
 * local index
 
 Stack
 * → value
 
 */
private func pushLocal(execution: ScriptExecutionContext) throws {
    
    let index = execution.immediate(at: 1)
    let value = try execution.thread.local(at: index)
    execution.thread.stack.push(value)
    
    //print("[\(execution.thread.id)] push local[\(index)] \(value)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10021004
 * static index
 
 Stack
 * → value
 
 */
private func pushStatic(execution: ScriptExecutionContext) throws {
    
    let index = execution.immediate(at: 1)
    let value = try execution.process.static(at: index)
    execution.thread.stack.push(value)
    
    //print("[\(execution.thread.id)] push static[\(index)] \(value)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10022000
 
 Stack
 * → value: 0
 
 */
private func stackAllocate(execution: ScriptExecutionContext) throws {
    
    execution.thread.stack.push(0)
    
    //print("[\(execution.thread.id)] stack allocate - push 0")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10023002
 * local index
 
 Stack
 * ← value
 
 */
private func setLocal(execution: ScriptExecutionContext) throws {
    
    let index = execution.immediate(at: 1)
    let value = try execution.thread.stack.pop()
    try execution.thread.setLocal(at: index, to: value)
    
    //print("[\(execution.thread.id)] pop to local[\(index)] \(value)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10023004
 * static index
 
 Stack
 * ← value
 
 */
private func setStatic(execution: ScriptExecutionContext) throws {
    
    let index = execution.immediate(at: 1)
    let value = try execution.thread.stack.pop()
    try execution.process.setStatic(at: index, to: value)
    
    //print("[\(execution.thread.id)] pop to static[\(index)] \(value)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10024000
 
 Stack
 * ← ???
 
 */
private func popStack(execution: ScriptExecutionContext) throws {
    
    let _ = try execution.thread.stack.pop()
    
    //print("[\(execution.thread.id)] pop to ??? \(value)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x1003X000
 
 Stack
 * ← right value
 * ← left value
 * → value
 
 */
private func perform(operation: (_StackValue, _StackValue) -> _StackValue, in execution: ScriptExecutionContext) throws {
    let right = try execution.thread.stack.pop()
    let left = try execution.thread.stack.pop()
    let result = operation(left, right)
    execution.thread.stack.push(result)
    execution.thread.instructionPointer += 1
}



/**
 
 Code
 * 0x10039000 or 0x1003A000 or 0x1003B000
 
 Stack
 * ← right value
 * ← left value
 * → value
 
 */
private func unknownOperator(execution: ScriptExecutionContext) throws {
    let opcode = execution.immediate(at: 0)
    let right = try execution.thread.stack.pop()
    let left = try execution.thread.stack.pop()
    print("[\(execution.thread.id)] Occurance of unknown operator (\(opcode): \(left) ??? \(right)")
    let result = left &+ right
    execution.thread.stack.push(result)
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x1005X000
 
 Stack
 * ← right value
 * ← left value
 * → value
 
 */
private func perform(comparison: (_StackValue, _StackValue) -> Bool, in execution: ScriptExecutionContext) throws {
    let right = try execution.thread.stack.pop()
    let left = try execution.thread.stack.pop()
    let result = _StackValue(comparison(left, right) ? 1 : 0)
    execution.thread.stack.push(result)
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x1005A000
 
 Stack
 * ← input value
 * → value
 
 */
private func perform(modification: (_StackValue) -> _StackValue, in execution: ScriptExecutionContext) throws {
    let value = try execution.thread.stack.pop()
    let result = modification(value)
    execution.thread.stack.push(result)
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10041000
 
 Stack
 * ← max value
 * ← min value
 * → value
 
 */
private func taRandom(min: _StackValue, max: _StackValue) -> _StackValue {
    guard min < max else { return min }
    return _StackValue.random(in: min...max)
}

/**
 
 Code
 * 0x10042000
 
 Stack
 * ← unit-value
 * → value
 
 */
private func getUnitValue(execution: ScriptExecutionContext) throws {

    let what = try execution.thread.stack.pop()
    var result: UnitScript.CodeUnit = 0
    if let uv = UnitScript.UnitValue(rawValue: what) {
        switch uv {
        case .activation, .standingFireOrders, .armored:
            result = 1
        case .health:
            result = 100
        case .inBuildStance, .busy, .yardOpen, .buggerOff:
            result = 0
        case .unitXZ, .unitY, .unitHeight, .groundHeight:
            result = 0
        default:
            ()
        }
    }
    execution.thread.stack.push(result)

    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10043000
 
 Stack
 * ← param
 * ← param
 * ← param
 * ← param
 * ← unit-value
 * → value
 
 */
private func getFunctionResult(execution: ScriptExecutionContext) throws {

    // pop(count: 4) returns items in push order (oldest first), so params[0] is
    // the first argument the script wrote — matching the TA convention where
    // get(PIECE_XZ, piece, 0, 0, 0) puts the piece index in the first slot.
    let params: [_StackValue] = try execution.thread.stack.pop(count: 4)
    let what = try execution.thread.stack.pop()

    var result: _StackValue = 0
    if let uv = UnitScript.UnitValue(rawValue: what) {
        switch uv {
        case .pieceXZ:
            if let pos = pieceWorldPosition(scriptPiece: params[0], execution: execution) {
                // UnitModel remaps 3DO (x, y, z) → SIMD (x, z, y) so pos.y is TA's Z
                // (horizontal depth) and pos.z is TA's Y (vertical height).
                result = packXZ(x: pos.x, z: pos.y)
            }
        case .pieceY:
            if let pos = pieceWorldPosition(scriptPiece: params[0], execution: execution) {
                result = _StackValue(pos.z)
            }
        case .xzAtan:
            let (x, z) = unpackXZ(params[0])
            result = taAtan2(z: z, x: x)
        case .xzHypot:
            let (x, z) = unpackXZ(params[0])
            result = taHypot(x: x, z: z)
        case .atan:
            result = taAtan2(z: GameFloat(params[1]), x: GameFloat(params[0]))
        case .hypot:
            result = taHypot(x: GameFloat(params[0]), z: GameFloat(params[1]))
        case .unitXZ, .unitY, .unitHeight, .groundHeight:
            result = 0
        default:
            ()
        }
    }
    execution.thread.stack.push(result)
    execution.thread.instructionPointer += 1
}

private func pieceWorldPosition(scriptPiece: UnitScript.CodeUnit, execution: ScriptExecutionContext) -> Vertex3f? {
    guard let modelIndex = try? execution.process.pieceIndex(at: scriptPiece) else { return nil }
    let model = execution.process.model
    guard modelIndex < model.pieces.count else { return nil }
    return model.pieceWorldPosition(modelIndex, instance: execution.model.pointee)
}

private func packXZ(x: GameFloat, z: GameFloat) -> UnitScript.CodeUnit {
    // TA packs the XZ coordinate as (x << 16) | (z & 0xFFFF), both as 16-bit
    // signed values. Piece offsets fit comfortably in 16 bits for normal units.
    let xi = max(-32768, min(32767, Int(x.rounded()))) & 0xFFFF
    let zi = max(-32768, min(32767, Int(z.rounded()))) & 0xFFFF
    return UnitScript.CodeUnit(truncatingIfNeeded: (xi << 16) | zi)
}

private func unpackXZ(_ packed: UnitScript.CodeUnit) -> (GameFloat, GameFloat) {
    let xRaw = Int(packed) >> 16
    var zRaw = Int(packed) & 0xFFFF
    if zRaw >= 0x8000 { zRaw -= 0x10000 }
    return (GameFloat(xRaw), GameFloat(zRaw))
}

/// TA represents a full turn as 65536 angle units. Returns atan2(z, x) remapped to that range.
private func taAtan2(z: GameFloat, x: GameFloat) -> UnitScript.CodeUnit {
    guard x != 0 || z != 0 else { return 0 }
    let radians = atan2(z, x)
    let turns = radians / (2 * .pi)
    return UnitScript.CodeUnit(truncatingIfNeeded: Int((turns * 65536).rounded()))
}

private func taHypot(x: GameFloat, z: GameFloat) -> UnitScript.CodeUnit {
    let h = hypot(x, z)
    return UnitScript.CodeUnit(truncatingIfNeeded: Int(h.rounded()))
}

/**
 
 Code
 * 0x10061000
 * module index
 * param count
 
 Stack
 * ← param * param count
 
 */
private func startScript(execution: ScriptExecutionContext) throws {
    
    let moduleIndex = execution.immediate(at: 1)
    let paramCount = execution.immediate(at: 2)
    
    let module = try execution.process.module(at: moduleIndex)
    let params = try execution.thread.stack.pop(count: Int(paramCount))

    execution.process.startScript(module, parameters: params)
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10062000
 * module index
 * param count
 
 Stack
 * ← param * `param count`
 
 */
private func callScript(execution: ScriptExecutionContext) throws {
    
    let moduleIndex = execution.immediate(at: 1)
    let paramCount = execution.immediate(at: 2)
    
    let module = try execution.process.module(at: moduleIndex)
    let params = try execution.thread.stack.pop(count: Int(paramCount))

    execution.thread.instructionPointer += 3
    execution.thread.callScript(module, parameters: params)
}

/**
 
 Code
 * 0x10064000
 * code offset
 
 */
private func jumpToOffset(execution: ScriptExecutionContext) throws {
    
    let joffset = execution.immediate(at: 1)
    
    execution.thread.instructionPointer = Int(joffset)
}

/**
 
 Code
 * 0x10065000
 
 Stack
 * ← value
 
 */
private func returnResult(execution: ScriptExecutionContext) throws {
    
    let value = try execution.thread.stack.pop()
    execution.thread.instructionPointer += 1
    execution.thread.`return`(with: value)
}

/**
 
 Code
 * 0x10066000
 * code offset
 
 Stack
 * ← value
 
 */
private func jumpToOffsetIfFalse(execution: ScriptExecutionContext) throws {
    
    let joffset = execution.immediate(at: 1)
    let condition = try execution.thread.stack.pop()
    
    if condition != 0 {
        execution.thread.instructionPointer += 2
    }
    else {
        execution.thread.instructionPointer = Int(joffset)
    }
}

/**
 
 Code
 * 0x10067000
 
 Stack
 * ← value
 
 */
private func signal(execution: ScriptExecutionContext) throws {
    
    let mask = try execution.thread.stack.pop()
    execution.process.signalThreads(with: mask, except: execution.thread)
    
    print("[\(execution.thread.id)] Signal \(mask)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10068000
 
 Stack
 * ← value
 
 */
private func setSignalMask(execution: ScriptExecutionContext) throws {
    
    let mask = try execution.thread.stack.pop()
    execution.thread.signalMask = mask
    
    print("[\(execution.thread.id)] Set Signal Mask \(mask)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10071000
 * piece index
 
 Stack
 * ← value
 
 */
private func explode(execution: ScriptExecutionContext) throws {
    
    let piece = execution.immediate(at: 1)
    let how = try execution.thread.stack.pop()
    
    print("[\(execution.thread.id)] Explode \(piece) type \(how)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10072000
 * sound index
 
 */
private func playSound(execution: ScriptExecutionContext) throws {
    
    let sound = execution.immediate(at: 1)
    
    print("[\(execution.thread.id)] Play Sound \(sound)")
    execution.thread.instructionPointer += 2
}

/**
 
 Code
 * 0x10073000
 * ???
 * ???
 
 */
private func mapCommand(execution: ScriptExecutionContext) throws {
    
    let a = execution.immediate(at: 1)
    let b = execution.immediate(at: 2)
    
    print("[\(execution.thread.id)] map command: \(a) \(b)")
    execution.thread.instructionPointer += 3
}

/**
 
 Code
 * 0x10082000
 
 Stack
 * ← value
 * ← unit-value
 
 */
private func setUnitValue(execution: ScriptExecutionContext) throws {
    
    let value = try execution.thread.stack.pop()
    let what = try execution.thread.stack.pop()
    
    print("[\(execution.thread.id)] Set Unit-Value[\(what)] to \(value)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10083000
 
 Stack
 * ← ???
 * ← piece
 * ← unit
 
 */
private func attachUnit(execution: ScriptExecutionContext) throws {
    
    let something = try execution.thread.stack.pop()
    let piece = try execution.thread.stack.pop()
    let unit = try execution.thread.stack.pop()
    
    print("[\(execution.thread.id)] Attach Unit \(unit) to \(piece) // ??? \(something)")
    execution.thread.instructionPointer += 1
}

/**
 
 Code
 * 0x10084000
 
 Stack
 * ← unit
 
 */
private func dropUnit(execution: ScriptExecutionContext) throws {
    
    let unit = try execution.thread.stack.pop()
    
    print("[\(execution.thread.id)] Drop Unit \(unit)")
    execution.thread.instructionPointer += 1
}

// MARK:- Stack Helpers

private typealias _StackValue = UnitScript.CodeUnit

// MARK:- Operator Helpers

private extension UnitScript.CodeUnit {
    
    var linearValue: GameFloat { return GameFloat(self) / LINEAR_CONSTANT }
    var angularValue: GameFloat { return GameFloat(self) / ANGULAR_CONSTANT }
    
    static func booleanAnd(lhs: _StackValue, rhs: _StackValue) -> _StackValue {
        return ((lhs != 0) && (rhs != 0)) ? 1 : 0
    }
    static func booleanOr(lhs: _StackValue, rhs: _StackValue) -> _StackValue {
        return ((lhs != 0) || (rhs != 0)) ? 1 : 0
    }
    static func booleanNot(value: _StackValue) -> _StackValue {
        return (value != 0) ? 0 : 1
    }
    
}

private func operatorFunc(operation: @escaping (_StackValue, _StackValue) -> _StackValue) -> Instruction {
    return { (execution: ScriptExecutionContext) in
        try perform(operation: operation, in: execution)
    }
}

private func operatorFunc(comparison: @escaping (_StackValue, _StackValue) -> Bool) -> Instruction {
    return { (execution: ScriptExecutionContext) in
        try perform(comparison: comparison, in: execution)
    }
}

private func operatorFunc(modification: @escaping (_StackValue) -> _StackValue) -> Instruction {
    return { (execution: ScriptExecutionContext) in
        try perform(modification: modification, in: execution)
    }
}
