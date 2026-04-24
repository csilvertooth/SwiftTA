//
//  main.swift
//  AEX-MapEditor
//
//  Explicit AppKit bootstrap. Using @main on an NSApplicationDelegate
//  class relies on NSApplicationMain, which reads NSMainNibFile from
//  Info.plist to locate the delegate — and this app deliberately ships
//  without a MainMenu.xib. Wiring the delegate up here ensures the
//  applicationWill/DidFinishLaunching callbacks actually fire so the
//  programmatic menu bar gets installed.
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
