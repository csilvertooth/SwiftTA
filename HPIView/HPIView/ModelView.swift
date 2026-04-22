//
//  ModelView.swift
//  HPIView
//
//  Created by Logan Jones on 7/5/18.
//  Copyright © 2018 Logan Jones. All rights reserved.
//

import AppKit
import SwiftTA_Core

class ModelViewController: NSViewController, PieceHierarchyViewDelegate {

    private(set) var viewState = ModelViewState()
    private var modelLoader: ModelViewLoader!
    private let pieceView = PieceHierarchyView(frame: .zero)
    private let splitView = NSSplitView()

    func pieceHierarchyView(_ view: PieceHierarchyView, didSelectPieceAt index: UnitModel.Pieces.Index?) {
        viewState.highlightedPieceIndex = index.map(Int32.init) ?? -1
    }

    override func loadView() {
        let defaultFrame = NSRect(x: 0, y: 0, width: 800, height: 480)

        let renderView: NSView
        if let modelView: NSView & ModelViewLoader = nil
            ?? MetalModelView(modelViewFrame: defaultFrame, stateProvider: self)
            ?? OpenglModelView(modelViewFrame: defaultFrame, stateProvider: self)
        {
            renderView = modelView
            modelLoader = modelView
        }
        else {
            renderView = NSView(frame: defaultFrame)
            modelLoader = DummyModelViewLoader()
        }

        splitView.dividerStyle = .thin
        splitView.isVertical = false
        splitView.autoresizingMask = [.width, .height]
        splitView.frame = defaultFrame
        splitView.addArrangedSubview(renderView)
        splitView.addArrangedSubview(pieceView)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)
        view = splitView
        pieceView.selectionDelegate = self
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if splitView.arrangedSubviews.count >= 2 {
            let total = splitView.bounds.height
            if total > 0 {
                splitView.setPosition(total * 0.6, ofDividerAt: 0)
            }
        }
    }

    func load(_ model: UnitModel, script: UnitScript? = nil) throws {
        viewState.highlightedPieceIndex = -1
        viewState.zoom = 1.0
        viewState.rotateX = 0
        viewState.rotateY = 0
        viewState.rotateZ = 160
        let extent = model.maxWorldExtent
        viewState.autoFitSceneWidth = max(ModelViewState.baseSceneWidth, extent * 2.3)
        try modelLoader.load(model)
        pieceView.apply(model: model, script: script)
        recomputeSceneSize()
    }

}

extension ModelViewController: ModelViewStateProvider {

    func viewportChanged(to size: CGSize) {
        viewState.viewportSize = size
        viewState.aspectRatio = Float(viewState.viewportSize.height) / Float(viewState.viewportSize.width)
        recomputeSceneSize()
    }

    private func recomputeSceneSize() {
        let base = viewState.autoFitSceneWidth > 0 ? viewState.autoFitSceneWidth : ModelViewState.baseSceneWidth
        let w = base / viewState.zoom
        viewState.sceneSize = (width: w, height: w * viewState.aspectRatio)
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
        recomputeSceneSize()
    }

    override func magnify(with event: NSEvent) {
        let factor = Float(1.0 + event.magnification)
        let newZoom = max(0.1, min(32.0, viewState.zoom * factor))
        viewState.zoom = newZoom
        recomputeSceneSize()
    }

    override func keyDown(with event: NSEvent) {
        switch event.characters {
        case .some("w"):
            var drawMode = viewState.drawMode
            let i = drawMode.rawValue
            if let mode = ModelViewState.DrawMode(rawValue: i+1) { drawMode = mode }
            else { drawMode = .solid }
            viewState.drawMode = drawMode
        case .some("l"):
            viewState.lighted = !viewState.lighted
        case .some("="), .some("+"):
            viewState.zoom = min(32.0, viewState.zoom * 1.25)
            recomputeSceneSize()
        case .some("-"), .some("_"):
            viewState.zoom = max(0.1, viewState.zoom / 1.25)
            recomputeSceneSize()
        case .some("0"):
            viewState.zoom = 1.0
            viewState.rotateX = 0
            viewState.rotateY = 0
            viewState.rotateZ = 160
            recomputeSceneSize()
        default:
            ()
        }
    }

}

struct ModelViewState {

    var viewportSize = CGSize()
    var aspectRatio: Float = 1
    var sceneSize: (width: Float, height: Float) = (0,0)

    static let gridSize = 16
    static let baseSceneWidth: Float = 320

    var drawMode = DrawMode.outlined
    var textured = false
    var lighted = true

    var rotateZ: GLfloat = 160
    var rotateX: GLfloat = 0
    var rotateY: GLfloat = 0

    var zoom: Float = 1.0
    var autoFitSceneWidth: Float = 0
    var highlightedPieceIndex: Int32 = -1

    enum DrawMode: Int {
        case solid
        case wireframe
        case outlined
    }

}

protocol ModelViewLoader {
    func load(_ model: UnitModel) throws
}
protocol ModelViewStateProvider: AnyObject {
    var viewState: ModelViewState { get }
    func viewportChanged(to size: CGSize)
    func mouseDragged(with event: NSEvent)
    func keyDown(with event: NSEvent)
}

private struct DummyModelViewLoader: ModelViewLoader {
    func load(_ model: UnitModel) throws {
        throw RuntimeError("No valid model view available to load model.")
    }
}
