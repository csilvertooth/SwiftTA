//
//  PlaybackControlsView.swift
//  TAassets
//

import AppKit

protocol PlaybackControlsViewDelegate: AnyObject {
    func playbackControls(_ view: PlaybackControlsView, didChangeSpeed speed: Float)
    func playbackControlsDidRequestStep(_ view: PlaybackControlsView)
    func playbackControls(_ view: PlaybackControlsView, didChooseScript name: String)
}

final class PlaybackControlsView: NSView {

    weak var delegate: PlaybackControlsViewDelegate?

    private let playButton = NSButton(title: "Pause", target: nil, action: nil)
    private let stepButton = NSButton(title: "Step", target: nil, action: nil)
    private let speedSlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 2.0,
                                       target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "1.00x")
    private let scriptPopup = NSPopUpButton(frame: .zero, pullsDown: true)

    private var lastNonZeroSpeed: Float = 1.0
    private var scriptFunctions: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 28)
    }

    private func setup() {
        playButton.bezelStyle = .rounded
        playButton.controlSize = .small
        playButton.target = self
        playButton.action = #selector(togglePlayPause)

        stepButton.bezelStyle = .rounded
        stepButton.controlSize = .small
        stepButton.target = self
        stepButton.action = #selector(stepTapped)

        speedSlider.target = self
        speedSlider.action = #selector(speedChanged)
        speedSlider.controlSize = .small
        speedSlider.numberOfTickMarks = 5
        speedSlider.allowsTickMarkValuesOnly = false

        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speedLabel.alignment = .right

        scriptPopup.controlSize = .small
        scriptPopup.pullsDown = true
        scriptPopup.removeAllItems()
        scriptPopup.addItem(withTitle: "Run script…")

        let stack = NSStackView(views: [playButton, stepButton, speedSlider, speedLabel, scriptPopup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            speedSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            speedLabel.widthAnchor.constraint(equalToConstant: 52),
            scriptPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
        ])
    }

    func reset(scriptFunctions: [String]) {
        self.scriptFunctions = scriptFunctions
        scriptPopup.removeAllItems()
        scriptPopup.addItem(withTitle: "Run script…")
        for name in scriptFunctions {
            let item = NSMenuItem(title: name,
                                  action: #selector(scriptMenuChanged(_:)),
                                  keyEquivalent: "")
            item.target = self
            scriptPopup.menu?.addItem(item)
        }
        speedSlider.floatValue = 1.0
        updateSpeedLabel(1.0)
        lastNonZeroSpeed = 1.0
        playButton.title = "Pause"
    }

    @objc private func togglePlayPause() {
        if speedSlider.floatValue == 0 {
            let restored = lastNonZeroSpeed > 0 ? lastNonZeroSpeed : 1.0
            speedSlider.floatValue = restored
            updateSpeedLabel(restored)
            playButton.title = "Pause"
            delegate?.playbackControls(self, didChangeSpeed: restored)
        } else {
            lastNonZeroSpeed = speedSlider.floatValue
            speedSlider.floatValue = 0
            updateSpeedLabel(0)
            playButton.title = "Play"
            delegate?.playbackControls(self, didChangeSpeed: 0)
        }
    }

    @objc private func stepTapped() {
        if speedSlider.floatValue != 0 {
            lastNonZeroSpeed = speedSlider.floatValue
            speedSlider.floatValue = 0
            updateSpeedLabel(0)
            playButton.title = "Play"
            delegate?.playbackControls(self, didChangeSpeed: 0)
        }
        delegate?.playbackControlsDidRequestStep(self)
    }

    @objc private func speedChanged() {
        let v = speedSlider.floatValue
        updateSpeedLabel(v)
        if v != 0 { lastNonZeroSpeed = v }
        playButton.title = (v == 0) ? "Play" : "Pause"
        delegate?.playbackControls(self, didChangeSpeed: v)
    }

    @objc private func scriptMenuChanged(_ sender: NSMenuItem) {
        guard let index = scriptPopup.menu?.index(of: sender), index > 0 else { return }
        let idx = index - 1
        guard scriptFunctions.indices.contains(idx) else { return }
        delegate?.playbackControls(self, didChooseScript: scriptFunctions[idx])
        scriptPopup.selectItem(at: 0)
    }

    private func updateSpeedLabel(_ value: Float) {
        speedLabel.stringValue = String(format: "%.2fx", value)
    }
}
