//
//  UnitView.swift
//  TAassets
//
//  Created by Logan Jones on 7/5/18.
//  Copyright © 2018 Logan Jones. All rights reserved.
//

import AppKit
import SwiftTA_Core

class UnitViewController: NSViewController {
    
    private(set) var viewState = UnitViewState()
    private var unitView: UnitViewLoader!

    private var unit: UnitInstance?
    private var loadTime: Double = 0
    private var shouldStartMoving = false
    private var lastScriptHeartbeat: Double = 0
    
    override func loadView() {
        let defaultFrame = NSRect(x: 0, y: 0, width: 640, height: 480)
        
        if let modelView: NSView & UnitViewLoader = nil
            ?? MetalUnitView(modelViewFrame: defaultFrame, stateProvider: self)
            ?? OpenglUnitView(modelViewFrame: defaultFrame, stateProvider: self)
        {
            view = modelView
            unitView = modelView
        }
        else {
            view = NSView(frame: defaultFrame)
            unitView = DummyUnitViewLoader()
        }
    }
    
    func load(_ info: UnitInfo,
              _ model: UnitModel,
              _ script: UnitScript,
              _ texture: UnitTextureAtlas,
              _ filesystem: FileSystem,
              _ palette: Palette) throws {
        viewState.zoom = 1.0
        viewState.rotateX = 0
        viewState.rotateY = 0
        viewState.rotateZ = 160
        viewState.highlightedPieceIndex = -1
        viewState.playbackSpeed = 1.0

        let newUnit = UnitInstance(
            info: info,
            model: model,
            modelInstance: UnitModel.Instance(for: model),
            script: script,
            scriptContext: try UnitScript.Context(script, model))
        
        try unitView.load(info, model, script, texture, filesystem, palette)
        
        loadTime = getTime()
        newUnit.scriptContext.startScript("Create")
        shouldStartMoving = newUnit.info.maxVelocity > 0
        
        viewState.isMoving = false
        viewState.movement = 0
        viewState.model = newUnit.model
        viewState.modelInstance = newUnit.modelInstance
        
        unit = newUnit
        computeSceneSize()
    }
    
    func clear() {
        unit = nil
        viewState.model = nil
        viewState.modelInstance = nil
        viewState.highlightedPieceIndex = -1
        unitView.clear()
    }

    func setHighlightedPiece(_ index: UnitModel.Pieces.Index?) {
        viewState.highlightedPieceIndex = index.map(Int32.init) ?? -1
    }

    var availableScriptFunctions: [String] {
        unit?.script.modules.map { $0.name } ?? []
    }

    func setPlaybackSpeed(_ speed: Float) {
        viewState.playbackSpeed = max(0, min(4, speed))
    }

    var playbackSpeed: Float { viewState.playbackSpeed }

    func startScript(_ name: String) {
        guard var unit = unit else {
            Swift.print("startScript(\(name)) skipped: no loaded unit")
            return
        }
        let before = unit.scriptContext.threads.count
        unit.scriptContext.startScript(name)
        let after = unit.scriptContext.threads.count
        Swift.print("startScript(\(name)): threads \(before) -> \(after), module found: \(unit.script.module(named: name) != nil), playbackSpeed=\(viewState.playbackSpeed)")
        self.unit = unit
    }

    func stepOnce(by duration: Double = 1.0 / 30.0) {
        guard var unit = unit else { return }
        unit.scriptContext.run(for: &unit.modelInstance, on: self)
        unit.scriptContext.applyAnimations(to: &unit.modelInstance, for: GameFloat(duration))
        viewState.modelInstance = unit.modelInstance
        self.unit = unit
    }
    
    private func computeSceneSize() {
        let footprintWidth = GameFloat( ((unit?.info.footprint.width ?? 2) + 8) * ModelViewState.gridSize )
        let extent = viewState.model?.maxWorldExtent ?? 0
        // Model fits in a box of side 2·extent centered at the origin. Add 20%
        // margin, then pick a scene width that also guarantees the scene height
        // (= sceneWidth·aspectRatio) is big enough to hold the full box. Without
        // the aspectRatio divisor a very wide window would crop tall mod units.
        let modelDiameter = extent * 2.4
        let aspectRatio = max(GameFloat(0.1), viewState.aspectRatio)
        let sceneWidthNeeded = max(modelDiameter, modelDiameter / aspectRatio)
        let baseWidth = max(footprintWidth, sceneWidthNeeded)
        let w = (baseWidth > 0 ? baseWidth : footprintWidth) / GameFloat(viewState.zoom)
        viewState.sceneSize = Size2f(width: w, height: w * viewState.aspectRatio)
    }
    
}

private extension UnitViewController {
    
    struct UnitInstance {
        var info: UnitInfo
        var model: UnitModel
        var modelInstance: UnitModel.Instance
        var script: UnitScript
        var scriptContext: UnitScript.Context
    }
    
}

extension UnitViewController: UnitViewStateProvider {
    
    func viewportChanged(to size: CGSize) {
        viewState.viewportSize = Size2f(size)
        viewState.aspectRatio = viewState.viewportSize.height / viewState.viewportSize.width
        computeSceneSize()
    }
    
    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) { viewState.rotateX += GLfloat(event.deltaX) }
        else if event.modifierFlags.contains(.option) { viewState.rotateY += GLfloat(event.deltaX) }
        else { viewState.rotateZ += GLfloat(event.deltaX) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        guard delta != 0 else { return }
        let factor = exp(delta * 0.02)
        let newZoom = max(0.1, min(32.0, viewState.zoom * factor))
        guard newZoom != viewState.zoom else { return }
        viewState.zoom = newZoom
        computeSceneSize()
    }

    override func magnify(with event: NSEvent) {
        let factor = Float(1.0 + event.magnification)
        let newZoom = max(0.1, min(32.0, viewState.zoom * factor))
        viewState.zoom = newZoom
        computeSceneSize()
    }

    override func keyDown(with event: NSEvent) {
        switch event.characters {
        case .some("w"):
            var drawMode = viewState.drawMode
            let i = drawMode.rawValue
            if let mode = UnitViewState.DrawMode(rawValue: i+1) { drawMode = mode }
            else { drawMode = .solid }
            viewState.drawMode = drawMode
        case .some("t"):
            viewState.textured = !viewState.textured
        case .some("l"):
            viewState.lighted = !viewState.lighted
        case .some("="), .some("+"):
            viewState.zoom = min(32.0, viewState.zoom * 1.25)
            computeSceneSize()
        case .some("-"), .some("_"):
            viewState.zoom = max(0.1, viewState.zoom / 1.25)
            computeSceneSize()
        case .some("0"):
            viewState.zoom = 1.0
            viewState.rotateX = 0
            viewState.rotateY = 0
            viewState.rotateZ = 160
            computeSceneSize()
        default:
            ()
        }
    }
    
    func updateAnimatingState(deltaTime: Double) {
        guard var unit = unit else { return }

        let speed = viewState.playbackSpeed
        if speed <= 0 {
            viewState.modelInstance = unit.modelInstance
            self.unit = unit
            return
        }
        let scaledDelta = deltaTime * Double(speed)

        // Emit a per-second heartbeat so we can tell whether scripts are
        // advancing at all. Logs thread count + queued animation count.
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastScriptHeartbeat > 1.0 {
            lastScriptHeartbeat = now
            Swift.print("script heartbeat: threads=\(unit.scriptContext.threads.count), anims=\(unit.scriptContext.animations.count), playbackSpeed=\(speed)")
        }

        if shouldStartMoving && getTime() > loadTime + 1 {
            unit.scriptContext.startScript("StartMoving")
            shouldStartMoving = false
            viewState.isMoving = true
            viewState.speed = 0
        }

        unit.scriptContext.run(for: &unit.modelInstance, on: self)
        unit.scriptContext.applyAnimations(to: &unit.modelInstance, for: GameFloat(scaledDelta))

        if viewState.isMoving {
            let dt = GameFloat(scaledDelta * 10)
            let acceleration = unit.info.acceleration
            let maxSpeed = unit.info.maxVelocity
            var currentSpeed = viewState.speed

            if currentSpeed < maxSpeed {
                currentSpeed = min(currentSpeed + dt * acceleration, maxSpeed)
            }
            viewState.movement += dt * currentSpeed
            viewState.speed = currentSpeed

            let gridSize = GameFloat(UnitViewState.gridSize)
            if viewState.movement > gridSize {
                viewState.movement -= gridSize
            }
        }

        viewState.modelInstance = unit.modelInstance
        self.unit = unit
    }
    
}

extension UnitViewController: ScriptMachine {
    
    func getTime() -> Double {
        return Date.timeIntervalSinceReferenceDate
    }
    
}

struct UnitViewState {
    
    var viewportSize: Size2f = .zero
    var aspectRatio: GameFloat = 1
    var sceneSize: Size2f = .zero
    
    static let gridSize = 16
    
    var drawMode = DrawMode.solid
    var textured = true
    var lighted = false
    
    var rotateZ: GLfloat = 160
    var rotateX: GLfloat = 0
    var rotateY: GLfloat = 0
    
    var model: UnitModel?
    var modelInstance: UnitModel.Instance?

    var zoom: Float = 1.0
    var highlightedPieceIndex: Int32 = -1
    var playbackSpeed: Float = 1.0

    var isMoving = false
    var speed: GameFloat = 0
    var movement: GameFloat = 0
    
    enum DrawMode: Int {
        case solid
        case wireframe
        case outlined
    }
    
}

protocol UnitViewLoader {
    func load(_ info: UnitInfo,
              _ model: UnitModel,
              _ script: UnitScript,
              _ texture: UnitTextureAtlas,
              _ filesystem: FileSystem,
              _ palette: Palette) throws
    func clear()
}
protocol UnitViewStateProvider: AnyObject {
    var viewState: UnitViewState { get }
    func viewportChanged(to size: CGSize)
    func mouseDragged(with event: NSEvent)
    func keyDown(with event: NSEvent)
    func updateAnimatingState(deltaTime: Double)
}

private struct DummyUnitViewLoader: UnitViewLoader {
    
    func load(_ info: UnitInfo,
              _ model: UnitModel,
              _ script: UnitScript,
              _ texture: UnitTextureAtlas,
              _ filesystem: FileSystem,
              _ palette: Palette) throws {
        throw RuntimeError("No valid view available to load unit.")
    }
    
    func clear() {}
    
}
