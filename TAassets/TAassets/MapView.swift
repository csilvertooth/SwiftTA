//
//  MapView.swift
//  TAassets
//
//  Created by Logan Jones on 7/18/18.
//  Copyright © 2018 Logan Jones. All rights reserved.
//

import AppKit
import SwiftTA_Core

class MapViewController: NSViewController {
    
    private var mapView: MapViewLoader!
    
    override func loadView() {
        let deafultFrame = NSRect(x: 0, y: 0, width: 640, height: 480)
        
        if false { /* Nothing to see here */ }
        else if let metal = MetalMapView(tntViewFrame: deafultFrame) {
            view = metal
            mapView = metal
        }
        else {
            let cocoa = CocoaMapView(frame: deafultFrame)
            view = cocoa
            mapView = cocoa
        }
    }
    
    func load(_ mapName: String, from filesystem: FileSystem) throws {
        try mapView.load(mapName, from: filesystem)
    }

    func clear() {
        mapView.clear()
    }

    func setOverlayMode(_ mode: MapOverlayMode) {
        mapView.setOverlayMode(mode)
    }

    func setSlopeThreshold(_ threshold: Int) {
        mapView.setSlopeThreshold(threshold)
    }
}

protocol MapViewLoader {
    func load(_ mapName: String, from filesystem: FileSystem) throws
    func clear()
    func setOverlayMode(_ mode: MapOverlayMode)
    func setSlopeThreshold(_ threshold: Int)
}

extension MapViewLoader {
    func setOverlayMode(_ mode: MapOverlayMode) {}
    func setSlopeThreshold(_ threshold: Int) {}
}
